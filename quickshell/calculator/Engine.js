// Own parser: typed-in JavaScript is never executed.
function evaluate(source) {
    const s = source.replace(/,/g, ".").replace(/×/g, "*").replace(/÷/g, "/").replace(/−/g, "-").replace(/\s/g, "");
    let pos = 0;
    function atom() {
        if (s[pos] === "+") { pos++; return atom(); }
        if (s[pos] === "-") { pos++; return -atom(); }
        let value;
        if (s[pos] === "(") {
            pos++; value = sum();
            if (s[pos++] !== ")") throw Error("Missing closing bracket");
        } else {
            const match = s.slice(pos).match(/^(?:\d+(?:\.\d*)?|\.\d+)(?:e[+-]?\d+)?/i);
            if (!match) throw Error("Complete the expression");
            pos += match[0].length; value = Number(match[0]);
        }
        while (s[pos] === "%") { pos++; value /= 100; }
        return value;
    }
    function product() {
        let v = atom();
        while (s[pos] === "*" || s[pos] === "/") {
            const op = s[pos++], b = atom();
            if (op === "/" && b === 0) throw Error("Cannot divide by zero");
            v = op === "*" ? v * b : v / b;
        }
        return v;
    }
    function sum() {
        let v = product();
        while (s[pos] === "+" || s[pos] === "-") {
            const op = s[pos++], b = product();
            v = op === "+" ? v + b : v - b;
        }
        return v;
    }
    const result = sum();
    if (pos !== s.length) throw Error("Check the expression");
    if (!isFinite(result)) throw Error("Result is too large");
    return Number(result.toPrecision(12)).toString();
}
