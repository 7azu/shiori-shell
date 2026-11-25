pragma Singleton
import QtQuick
import "../calculator/Engine.js" as Engine

QtObject {
    property bool isOpen: false
    property string expression: ""
    property string result: "0"
    property string error: ""
    property bool completed: false
    property var history: []
    readonly property string preview: {
        if (!expression) return "0";
        try { return Engine.evaluate(expression); } catch (e) { return ""; }
    }
    function toggle() { isOpen = !isOpen; }
    function close() { isOpen = false; }
    function clear() { expression = ""; result = "0"; error = ""; completed = false; }
    function input(value) {
        error = "";
        if (value === "AC") { clear(); return; }
        if (value === "⌫") {
            expression = expression.slice(0, -1); completed = false; return;
        }
        if (value === "=") { calculate(); return; }
        if (value === "±") {
            if (!expression) expression = "-";
            else expression = "-(" + expression + ")";
            completed = false; return;
        }
        if (completed) {
            expression = /^[+−×÷%*/-]$/.test(value) ? result : "";
            completed = false;
        }
        if (expression.length < 200) expression += value === "," ? "." : value;
    }
    function calculate() {
        if (!expression) return;
        try {
            result = Engine.evaluate(expression);
            history = [{expression: expression, result: result}].concat(history).slice(0, 30);
            completed = true; error = "";
        } catch (e) { error = e.message; }
    }
    function recall(entry) {
        expression = entry.result; result = entry.result; completed = true; error = "";
    }
}
