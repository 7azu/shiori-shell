.pragma library

// Japanese numerals for the workspace numbers (1-99)
function kanjiNumber(n) {
    const d = ["", "一", "二", "三", "四", "五", "六", "七", "八", "九"];
    if (!(n >= 1 && n <= 99))
        return String(n);

    if (n < 10)
        return d[n];

    const tens = Math.floor(n / 10);
    return (tens > 1 ? d[tens] : "") + "十" + d[n % 10];
}
