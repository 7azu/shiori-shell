return {
  -- Build dir and import paths come from the .qmlls.ini (Quickshell creates it itself).
  -- Note: "--import-path" does not exist, qmlls aborts with it right away (only -I).
  cmd = { "qmlls" },
  filetypes = { "qml" },
  root_markers = { ".qmlls.ini", "CMakeLists.txt", ".git" },
}
