// LD_PRELOAD shim for linux-wallpaperengine (set by scripts/wallpaperengine_run.py).
//
// Problem: the engine loads the cursor theme (XCURSOR_THEME) exactly once when setting up its layer
// (wl_cursor_theme_load in WaylandOutputViewport.cpp) and attaches the same left_ptr image on every
// pointer enter (wl_cursor_image_get_buffer in WaylandOpenGLDriver.cpp). But the cursor color follows
// the wal colors (~/.config/wal/cursor/cursor-fade.py rewrites the theme files on a
// wallpaper change) - so over the desktop the color from the engine's start stayed, and
// the engine starts even BEFORE the color change.
//
// Solution: intercept wl_cursor_image_get_buffer for the engine's left_ptr image. If the theme's
// left_ptr file has changed since then (mtime/inode), load the theme fresh and return its buffer.
// Hotspot and size stay the same (only the color changes). Two generations
// are kept: the one before the last is then surely no longer attached to the cursor surface.
// Everything else goes unchanged to libwayland-cursor.
//
// Build (wallpaperengine_run.py does this itself, result in the cache, not in the repo):
//   cc -shared -fPIC -O2 -o cursor_follow_shim.so cursor_follow_shim.c -ldl

#define _GNU_SOURCE
#include <dlfcn.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <wayland-client.h>
#include <wayland-cursor.h>

#define MAX_THEMES 8

struct tracked {
    struct wl_cursor_theme *orig;      // theme the engine has loaded
    struct wl_cursor_image *image;     // its left_ptr image[0], which the engine keeps using
    char *name;
    int size;
    struct wl_shm *shm;
    struct wl_cursor_theme *cur, *prev; // freshly loaded generations (cur is in use)
    struct wl_cursor_image *cur_image;
    struct timespec mtime;
    ino_t ino;
    int known;                          // file state known at load time
};

static struct tracked themes[MAX_THEMES];
static int n_themes;

static struct wl_cursor_theme *(*real_load)(const char *, int, struct wl_shm *);
static struct wl_cursor *(*real_get_cursor)(struct wl_cursor_theme *, const char *);
static struct wl_buffer *(*real_get_buffer)(struct wl_cursor_image *);
static void (*real_destroy)(struct wl_cursor_theme *);

static void init(void) {
    if (real_load)
        return;
    real_load = dlsym(RTLD_NEXT, "wl_cursor_theme_load");
    real_get_cursor = dlsym(RTLD_NEXT, "wl_cursor_theme_get_cursor");
    real_get_buffer = dlsym(RTLD_NEXT, "wl_cursor_image_get_buffer");
    real_destroy = dlsym(RTLD_NEXT, "wl_cursor_theme_destroy");
}

// State of the theme's left_ptr file (search path like libwayland-cursor: XCURSOR_PATH or default)
static int file_state(const char *name, struct timespec *mtime, ino_t *ino) {
    if (!name || !*name)
        return 0;
    const char *home = getenv("HOME");
    const char *env = getenv("XCURSOR_PATH");
    char dirs[4096];
    if (env && *env)
        snprintf(dirs, sizeof dirs, "%s", env);
    else
        snprintf(dirs, sizeof dirs, "%s/.local/share/icons:%s/.icons:/usr/share/icons:/usr/share/pixmaps",
                 home ? home : "", home ? home : "");
    for (char *save = NULL, *dir = strtok_r(dirs, ":", &save); dir; dir = strtok_r(NULL, ":", &save)) {
        char path[PATH_MAX];
        struct stat st;
        if (dir[0] == '~' && home)
            snprintf(path, sizeof path, "%s%s/%s/cursors/left_ptr", home, dir + 1, name);
        else
            snprintf(path, sizeof path, "%s/%s/cursors/left_ptr", dir, name);
        if (stat(path, &st) == 0) {
            *mtime = st.st_mtim;
            *ino = st.st_ino;
            return 1;
        }
    }
    return 0;
}

struct wl_cursor_theme *wl_cursor_theme_load(const char *name, int size, struct wl_shm *shm) {
    init();
    struct wl_cursor_theme *theme = real_load(name, size, shm);
    if (theme && n_themes < MAX_THEMES) {
        struct tracked *t = &themes[n_themes++];
        memset(t, 0, sizeof *t);
        t->orig = theme;
        t->name = name ? strdup(name) : NULL;
        t->size = size;
        t->shm = shm;
        t->known = file_state(t->name, &t->mtime, &t->ino);
    }
    return theme;
}

struct wl_cursor *wl_cursor_theme_get_cursor(struct wl_cursor_theme *theme, const char *name) {
    init();
    struct wl_cursor *cursor = real_get_cursor(theme, name);
    if (cursor && cursor->image_count && name && strcmp(name, "left_ptr") == 0)
        for (int i = 0; i < n_themes; i++)
            if (themes[i].orig == theme && !themes[i].image)
                themes[i].image = cursor->images[0];
    return cursor;
}

struct wl_buffer *wl_cursor_image_get_buffer(struct wl_cursor_image *image) {
    init();
    for (int i = 0; i < n_themes; i++) {
        struct tracked *t = &themes[i];
        if (t->image != image)
            continue;
        struct timespec m;
        ino_t ino;
        if (t->known && file_state(t->name, &m, &ino)
            && (m.tv_sec != t->mtime.tv_sec || m.tv_nsec != t->mtime.tv_nsec || ino != t->ino)) {
            struct wl_cursor_theme *fresh = real_load(t->name, t->size, t->shm);
            struct wl_cursor *c = fresh ? real_get_cursor(fresh, "left_ptr") : NULL;
            if (c && c->image_count) {
                if (t->prev)
                    real_destroy(t->prev);
                t->prev = t->cur;
                t->cur = fresh;
                t->cur_image = c->images[0];
                t->mtime = m;
                t->ino = ino;
            } else if (fresh) {
                real_destroy(fresh);
            }
        }
        if (t->cur_image)
            return real_get_buffer(t->cur_image);
        break;
    }
    return real_get_buffer(image);
}
