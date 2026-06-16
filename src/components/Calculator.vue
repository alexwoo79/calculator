<script setup>
import { ref, computed, onMounted, onUnmounted } from "vue";

const inputText = ref("");
const numbers = ref([]);
const errorMsg = ref("");
const history = ref([]);
const copiedIdx = ref(-1);
const quickPasteText = ref("");
const displayResult = ref(null);
const lastInput = ref("");       // 上一次计算的输入
const lastResultValue = ref(null); // 上一次计算结果（数值，用于连算）
const aBound = ref(75);
const bBound = ref(50);
const cBound = ref(25);
const showGrade = ref(false);
const gradeSortKey = ref("rank");   // 默认按排名升序
const gradeSortAsc = ref(true);
const showTouchPad = ref(true);
const showCalcPad = ref(true); // 显示计算器按键面板
const showHints = ref(false);
const showStats = ref(false);  // 是否展示统计面板
const showPace = ref(true);    // 是否显示配速转换
const paceHints = new Set(['km', 'Hour', 'Min', 'Second']);

// ===== 全局 tooltip（绕过 overflow:hidden 裁剪）=====
const tooltip = ref({ show: false, text: '', x: 0, y: 0 });
function showTooltip(e, text) {
    const rect = e.target.getBoundingClientRect();
    tooltip.value = { show: true, text, x: rect.left + rect.width / 2, y: rect.bottom + 8 };
}
function hideTooltip() {
    tooltip.value.show = false;
}

// 表达式是否包含配速相关单位
const paceContext = computed(() => {
    const expr = lastInput.value.toLowerCase();
    const hasTime = /\b(hour|min|sec|second)\b/.test(expr);
    const hasDist = /\bkm\b/.test(expr);
    return { hasTime, hasDist, isSpeed: hasTime && hasDist && expr.includes('/') };
});

// 配速：仅当表达式含距离+时间+除法时显示
const paceText = computed(() => {
    if (!showPace.value || numbers.value.length !== 1) return null;
    if (!paceContext.value.isSpeed) return null;
    const speed = numbers.value[0];
    if (speed <= 0 || !isFinite(speed)) return null;
    const totalSec = (60 / speed) * 60;
    const min = Math.floor(totalSec / 60);
    const sec = Math.round(totalSec % 60);
    if (sec === 60) return `${min + 1}:00 /km`;
    return `${min}:${String(sec).padStart(2, '0')} /km`;
});

// 结果单位：仅当表达式含物理单位时显示
const resultUnit = computed(() => {
    if (!displayResult.value || numbers.value.length !== 1) return '';
    const { hasTime, hasDist, isSpeed } = paceContext.value;
    if (isSpeed) return 'km/h';                              // 速度
    if (hasTime && !hasDist) return 'h';                     // 纯时间
    if (hasDist && !hasTime) return 'km';                    // 纯距离
    return '';
});

// ===== 键盘按键反馈 =====
const activeKey = ref(null); // 当前高亮的按键标识
let audioCtx = null;

// 物理键盘 → 计算器按键映射
const keyMap = {
    '0': '0', '1': '1', '2': '2', '3': '3', '4': '4', '5': '5', '6': '6', '7': '7', '8': '8', '9': '9',
    '.': '.', ',': '.',
    '/': '÷', '*': '×', '-': '−', '+': '+',
    'Backspace': '⌫', 'Delete': '⌫',
    ' ': 'Space', 'Spacebar': 'Space',
    'Enter': '=', '=': '=',
    'Escape': 'AC',
    '(': '(', ')': ')',
    '^': '^', '%': '%',
};

function playClick() {
    if (!audioCtx) {
        try { audioCtx = new (window.AudioContext || window.webkitAudioContext)(); } catch { return; }
    }
    const osc = audioCtx.createOscillator();
    const gain = audioCtx.createGain();
    osc.connect(gain);
    gain.connect(audioCtx.destination);
    osc.type = 'sine';
    osc.frequency.setValueAtTime(1200, audioCtx.currentTime);
    osc.frequency.exponentialRampToValueAtTime(600, audioCtx.currentTime + 0.06);
    gain.gain.setValueAtTime(0.12, audioCtx.currentTime);
    gain.gain.exponentialRampToValueAtTime(0.001, audioCtx.currentTime + 0.08);
    osc.start(audioCtx.currentTime);
    osc.stop(audioCtx.currentTime + 0.08);
}

function onKeyDown(e) {
    // 左右方向键切换面板（输入框聚焦时不拦截）
    if (e.key === 'ArrowLeft' || e.key === 'ArrowRight') {
        const isInputFocused = document.activeElement?.tagName === 'INPUT';
        if (!isInputFocused) {
            e.preventDefault();
            showStats.value = e.key === 'ArrowRight';
            return;
        }
        return; // 输入框内正常移动光标
    }

    const mapped = keyMap[e.key];
    if (!mapped) return;
    e.preventDefault();
    activeKey.value = mapped;
    playClick();
    // 映射到计算器操作
    if (mapped === '=' || mapped === 'AC' || mapped === '⌫' || mapped === 'Space') {
        if (mapped === '=') handleKeyboardSubmit();
        else if (mapped === 'AC') calcClear();
        else if (mapped === '⌫') inputText.value = inputText.value.slice(0, -1);
        else if (mapped === 'Space') inputText.value += ' ';
    } else {
        inputText.value += mapped === '÷' ? '/' : mapped === '×' ? '*' : mapped === '−' ? '-' : mapped;
    }
}

function onKeyUp(e) {
    const mapped = keyMap[e.key];
    if (mapped && activeKey.value === mapped) {
        activeKey.value = null;
    }
}

onMounted(() => {
    window.addEventListener('keydown', onKeyDown);
    window.addEventListener('keyup', onKeyUp);
});

onUnmounted(() => {
    window.removeEventListener('keydown', onKeyDown);
    window.removeEventListener('keyup', onKeyUp);
});

// 计算器按键处理
const calcKeys = [
    // 数字行
    ['7', '8', '9', '÷'],
    ['4', '5', '6', '×'],
    ['1', '2', '3', '−'],
    ['0', '.', '⌫', '+'],
    ['(', ')', '^', '%'],
];
const calcFuncKeys = [];

function calcKeyTap(key) {
    playClick();
    if (key === '⌫') {
        inputText.value = inputText.value.slice(0, -1);
    } else if (key === 'Space') {
        inputText.value += ' ';
    } else if (key === '÷') {
        inputText.value += '/';
    } else if (key === '×') {
        inputText.value += '*';
    } else if (key === '−') {
        inputText.value += '-';
    } else {
        inputText.value += key;
    }
}

function calcFuncTap(fn) { }

function calcClear() {
    playClick();
    inputText.value = '';
    errorMsg.value = '';
    displayResult.value = null;
    lastInput.value = '';
    lastResultValue.value = null;
    numbers.value = [];
}

// 支持的数学函数提示
const functionHints = [
    // 三角函数
    "sin(x)", "cos(x)", "tan(x)",
    "asin(x)", "acos(x)", "atan(x)",
    "sind(x)", "cosd(x)", "tand(x)",
    "sinh(x)", "cosh(x)", "tanh(x)",
    // 幂指对
    "sqrt(x)", "cbrt(x)", "ln(x)", "lg(x)", "log(x)", "log2(x)",
    "pow(x,y)", "hypot(x,y)",
    // 取整/符号
    "abs(x)", "sign(x)", "floor(x)", "ceil(x)", "round(x)",
    // 组合/角度/进制
    "mod(x,y)", "deg(x)", "rad(x)",
    "nCr(n,r)", "nPr(n,r)", "x!", "x%",
    "hex2dec(x)", "bin2dec(x)",
    // 常量/字面量
    "pi", "e", "km", "Hour", "Min", "Second",
];

// 每个预设的 hover 提示
const hintTooltips = {
    "sin(x)": "正弦", "cos(x)": "余弦", "tan(x)": "正切",
    "asin(x)": "反正弦", "acos(x)": "反余弦", "atan(x)": "反正切",
    "sind(x)": "正弦(度)", "cosd(x)": "余弦(度)", "tand(x)": "正切(度)",
    "sinh(x)": "双曲正弦", "cosh(x)": "双曲余弦", "tanh(x)": "双曲正切",
    "sqrt(x)": "平方根 √", "cbrt(x)": "立方根 ∛",
    "ln(x)": "自然对数", "lg(x)": "常用对数(10)", "log(x)": "常用对数(10)", "log2(x)": "以2为底对数",
    "pow(x,y)": "x 的 y 次幂", "hypot(x,y)": "√(x²+y²)",
    "abs(x)": "绝对值", "sign(x)": "符号(±1/0)", "floor(x)": "向下取整", "ceil(x)": "向上取整", "round(x)": "四舍五入",
    "mod(x,y)": "取模", "deg(x)": "弧度→度", "rad(x)": "度→弧度",
    "nCr(n,r)": "组合数 C(n,r)", "nPr(n,r)": "排列数 P(n,r)", "x!": "阶乘", "x%": "百分比 ÷100",
    "hex2dec(x)": "十六进制→十进制", "bin2dec(x)": "二进制→十进制",
    "pi": "圆周率 π≈3.1416", "e": "自然常数 e≈2.7183",
    "km": "千米 (=1) · 距离单位", "Hour": "小时 (=1) · 时间单位",
    "Min": "分钟 (=1/60h) · 时间单位", "Second": "秒 (=1/3600h) · 简写 sec",
};

// 计算结果统计
const stats = computed(() => {
    if (numbers.value.length === 0) return null;
    const sorted = [...numbers.value].sort((a, b) => a - b);
    const sum = sorted.reduce((a, b) => a + b, 0);
    const avg = sum / sorted.length;
    const mid = Math.floor(sorted.length / 2);
    const median = sorted.length % 2 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
    const variance = sorted.reduce((s, v) => s + (v - avg) ** 2, 0) / sorted.length;
    return {
        count: sorted.length,
        sum,
        max: sorted[sorted.length - 1],
        min: sorted[0],
        avg,
        median,
        stddev: Math.sqrt(variance),
        range: sorted[sorted.length - 1] - sorted[0],
    };
});

// 排名表格数据（降序排列，1=最大，含分位%）
const rankedData = computed(() => {
    if (numbers.value.length === 0) return [];
    const N = numbers.value.length;
    const indexed = numbers.value.map((v, i) => ({ idx: i + 1, raw: v }));
    const sorted = [...indexed].sort((a, b) => b.raw - a.raw);
    let r = 0, prev = NaN;
    return sorted.map((item) => {
        if (item.raw !== prev) { r++; prev = item.raw; }
        const pct = N > 1 ? ((N - r) / (N - 1)) * 100 : 100;
        return { ...item, rank: r, pct: Math.round(pct * 10) / 10 };
    });
});

// 等级评定
const gradedData = computed(() => {
    return rankedData.value.map(r => {
        let grade;
        if (r.pct >= aBound.value) grade = 'A';
        else if (r.pct >= bBound.value) grade = 'B';
        else if (r.pct >= cBound.value) grade = 'C';
        else grade = 'D';
        return { ...r, grade };
    });
});

// 各等级计数
const gradeCounts = computed(() => {
    const counts = { A: 0, B: 0, C: 0, D: 0 };
    gradedData.value.forEach(r => counts[r.grade]++);
    return counts;
});

// 排序后的等级评定数据
const sortedGradeData = computed(() => {
    const data = [...gradedData.value];
    const key = gradeSortKey.value;
    const asc = gradeSortAsc.value;
    data.sort((a, b) => {
        let va, vb;
        if (key === "grade") {
            const order = { A: 1, B: 2, C: 3, D: 4 };
            va = order[a.grade];
            vb = order[b.grade];
        } else {
            va = a[key];
            vb = b[key];
        }
        if (va < vb) return asc ? -1 : 1;
        if (va > vb) return asc ? 1 : -1;
        return 0;
    });
    return data;
});

function toggleGradeSort(key) {
    if (gradeSortKey.value === key) {
        gradeSortAsc.value = !gradeSortAsc.value;
    } else {
        gradeSortKey.value = key;
        gradeSortAsc.value = true;
    }
}

function sortArrowFor(key) {
    if (gradeSortKey.value !== key) return '';
    return gradeSortAsc.value ? ' \u25B2' : ' \u25BC';
}

// 实时预览
const previewResult = computed(() => {
    const input = inputText.value.trim();
    if (!input) return null;
    try {
        return { value: formatNum(evaluateSingle(input)) };
    } catch {
        return null;
    }
});

// 阶乘
function factorial(n) {
    if (n < 0) throw new Error("阶乘不支持负数");
    if (!Number.isInteger(n)) throw new Error("阶乘仅支持整数");
    if (n > 170) throw new Error("阶乘数值过大");
    let r = 1;
    for (let i = 2; i <= n; i++) r *= i;
    return r;
}

// 组合数 nCr
function ncr(n, r) {
    if (r < 0 || r > n) throw new Error("nCr 参数无效");
    return Math.round(factorial(n) / (factorial(r) * factorial(n - r)));
}

// 排列数 nPr
function npr(n, r) {
    if (r < 0 || r > n) throw new Error("nPr 参数无效");
    return Math.round(factorial(n) / factorial(n - r));
}

function clearResults() {
    numbers.value = [];
    errorMsg.value = "";
    displayResult.value = null;
    lastResultValue.value = null;
}

// 历史记录点击复用
function fillFromHistory(item) {
    inputText.value = item.nums ? item.nums.map(formatNum).join(" ") : item.input;
    errorMsg.value = "";
}

// 批量粘贴处理
function handleQuickPaste() {
    errorMsg.value = "";
    const raw = quickPasteText.value.trim();
    if (!raw) return;
    // 按逗号、空格、换行分割
    const tokens = raw.split(/[,\s\n]+/);
    const nums = [];
    for (const token of tokens) {
        if (!token) continue;
        try {
            nums.push(evaluateSingle(token));
        } catch (err) {
            errorMsg.value = `"${token}": ${err.message || err}`;
            return;
        }
    }
    if (nums.length === 0) {
        errorMsg.value = "未解析到有效的数字";
        return;
    }
    numbers.value = nums;
    addHistory("粘贴", raw.slice(0, 40) + (raw.length > 40 ? "…" : ""), nums);
    quickPasteText.value = "";
}

// 一键复制
function copyToClipboard(text, idx) {
    navigator.clipboard.writeText(String(text));
    copiedIdx.value = idx;
    setTimeout(() => (copiedIdx.value = -1), 1200);
}

// 复制等级评定表格（TSV 格式，可直接粘贴到 Excel）
const gradeTableCopied = ref(false);
function copyGradeTable() {
    const header = ["序号", "数值", "排名", "分位%", "等级"];
    const rows = sortedGradeData.value.map(r => [
        r.idx,
        formatNum(r.raw),
        `#${r.rank}`,
        `${r.pct}%`,
        r.grade,
    ]);
    const tsv = [header, ...rows].map(row => row.join("\t")).join("\n");
    navigator.clipboard.writeText(tsv);
    gradeTableCopied.value = true;
    setTimeout(() => (gradeTableCopied.value = false), 1500);
}

// 将数学表达式字符串转换为可求值的形式
function prepareExpression(expr) {
    let prepared = expr.trim().toLowerCase();
    // 隐式乘法：数字与变量、变量与变量之间自动补 *
    const unitVars = 'km|hour|min|second|sec|pi|e';
    const timeVars = 'hour|min|second|sec';
    // 数字+单位 → 乘法: 5 km → 5*km, 30 min → 30*min
    prepared = prepared.replace(new RegExp(`(\\d)\\s+(${unitVars})\\b`, 'g'), '$1*$2');
    // 时间单位+数字 → 加法: min 30 → min + 30  (30*min 30*sec → 30*min + 30*sec)
    prepared = prepared.replace(new RegExp(`\\b(${timeVars})\\s+(\\d)`, 'g'), '$1 + $2');
    // 距离+数字 → 乘法: km 5 → km*5
    prepared = prepared.replace(new RegExp(`\\b(km)\\s+(\\d)`, 'g'), '$1*$2');
    // 单位+单位 → 乘法: km hour → km*hour
    prepared = prepared.replace(new RegExp(`\\b(${unitVars})\\s+(${unitVars})\\b`, 'g'), '$1*$2');
    // 无空格: 5km → 5*km
    prepared = prepared.replace(new RegExp(`(\\d)(${unitVars})\\b`, 'g'), '$1*$2');
    // 除法后时间表达式 → 括号包裹:
    // "5*km / 30*min" → "5*km / (30*min)"
    // "5*km / 30*min + 30*sec" → "5*km / (30*min + 30*sec)"
    prepared = prepared.replace(
        new RegExp(`/\\s*(\\d+(?:\\.\\d+)?\\s*\\*\\s*(?:${timeVars})\\b(?:\\s*\\+\\s*\\d+(?:\\.\\d+)?\\s*\\*\\s*(?:${timeVars})\\b)*)`, 'g'),
        (_, terms) => `/(${terms.trim()})`
    );
    // 百分号
    prepared = prepared.replace(/(\d+\.?\d*)%/g, "($1/100)");
    // 阶乘
    prepared = prepared.replace(/(\d+\.?\d*)!/g, "factorial($1)");
    // 组合与排列
    prepared = prepared.replace(/\bncr\s*\((\d+)\s*,\s*(\d+)\)/g, "ncr($1,$2)");
    prepared = prepared.replace(/\bnpr\s*\((\d+)\s*,\s*(\d+)\)/g, "npr($1,$2)");

    // 第1轮：直接映射到 Math.*（不依赖其他函数）
    prepared = prepared.replace(/\bfloor\b/g, "Math.floor");
    prepared = prepared.replace(/\bceil\b/g, "Math.ceil");
    prepared = prepared.replace(/\bround\b/g, "Math.round");
    prepared = prepared.replace(/\bsign\b/g, "Math.sign");
    prepared = prepared.replace(/\bcbrt\b/g, "Math.cbrt");
    prepared = prepared.replace(/\blog2\b/g, "Math.log2");
    prepared = prepared.replace(/\bhypot\b/g, "Math.hypot");
    prepared = prepared.replace(/\bsinh\b/g, "Math.sinh");
    prepared = prepared.replace(/\bcosh\b/g, "Math.cosh");
    prepared = prepared.replace(/\btanh\b/g, "Math.tanh");
    prepared = prepared.replace(/\basin\b/g, "Math.asin");
    prepared = prepared.replace(/\bacos\b/g, "Math.acos");
    prepared = prepared.replace(/\batan\b/g, "Math.atan");
    prepared = prepared.replace(/\blog\b/g, "Math.log10");

    // 第2轮：基础函数（sind/cosd/tand 等依赖它们，必须先替换）
    // 注意 \b 确保 sind 不会误匹配为 sin
    prepared = prepared.replace(/\bsin\b/g, "Math.sin");
    prepared = prepared.replace(/\bcos\b/g, "Math.cos");
    prepared = prepared.replace(/\btan\b/g, "Math.tan");
    prepared = prepared.replace(/\bpi\b/g, "Math.PI");
    prepared = prepared.replace(/\babs\b/g, "Math.abs");
    prepared = prepared.replace(/\bsqrt\b/g, "Math.sqrt");
    prepared = prepared.replace(/\bln\b/g, "Math.log");
    prepared = prepared.replace(/\blg\b/g, "Math.log10");
    prepared = prepared.replace(/\bpow\b/g, "Math.pow");
    prepared = prepared.replace(/\be\b(?![a-zA-Z])/g, "Math.E");

    // 第3轮：派生函数（语法糖，依赖第2轮已替换的基础函数）
    prepared = prepared.replace(/\bsind\(([^)]+)\)/g, "Math.sin(($1)*Math.PI/180)");
    prepared = prepared.replace(/\bcosd\(([^)]+)\)/g, "Math.cos(($1)*Math.PI/180)");
    prepared = prepared.replace(/\btand\(([^)]+)\)/g, "Math.tan(($1)*Math.PI/180)");
    prepared = prepared.replace(/\brad\(([^)]+)\)/g, "(($1)*Math.PI/180)");
    prepared = prepared.replace(/\bdeg\(([^)]+)\)/g, "(($1)*180/Math.PI)");
    prepared = prepared.replace(/\bmod\(([^,]+),([^)]+)\)/g, "(($1%$2+$2)%$2)");
    // 进制换算: hex2dec(ff) → parseInt("ff",16), bin2dec(1010) → parseInt("1010",2)
    prepared = prepared.replace(/\bhex2dec\(([a-f0-9]+)\)/g, 'parseInt("$1",16)');
    prepared = prepared.replace(/\bbin2dec\(([01]+)\)/g, 'parseInt("$1",2)');
    prepared = prepared.replace(/\^/g, "**");
    return prepared;
}

// 计算单个表达式
function evaluateSingle(expr) {
    const prepared = prepareExpression(expr);
    let result;
    try {
        // 使用 Function 构造器进行求值
        result = new Function("Math", "factorial", "ncr", "npr", "km", "Hour", "Min", "Second", "hour", "min", "second", "sec", `"use strict"; return (${prepared});`)(Math, factorial, ncr, npr, 1, 1, 1 / 60, 1 / 3600, 1, 1 / 60, 1 / 3600, 1 / 3600);
    } catch {
        throw new Error("请输入正确的表达式");
    }
    const num = Number(result);
    if (isNaN(num) || !isFinite(num)) {
        throw new Error("请输入正确的表达式");
    }
    return num;
}

// 点击预设函数按钮：如输入栏有有效数字，则将其作为参数嵌入表达式
function insertHint(hint) {
    playClick();
    const trimmed = inputText.value.trim();
    // 检查输入栏是否为一个有效数字（支持整数、小数、负数、科学计数法）
    const isNumber = trimmed !== "" && !isNaN(Number(trimmed)) && isFinite(Number(trimmed));

    if (hint.includes("(")) {
        // 带括号的函数，如 sin(x)、sqrt(x)、nCr(n,r) 等
        if (isNumber) {
            // 将数字嵌入第一个参数位
            inputText.value = hint.replace(/\([^)]*\)/, `(${trimmed})`);
        } else {
            inputText.value = trimmed ? trimmed + " " + hint : hint;
        }
    } else {
        // 不带括号的常量或模板，如 pi、e、0xff、x! 等
        if (isNumber && hint === "x!") {
            inputText.value = trimmed + "!";
        } else if (isNumber && hint === "x%") {
            inputText.value = trimmed + "%";
        } else {
            inputText.value = trimmed ? trimmed + " " + hint : hint;
        }
    }
}

// 键盘输入处理
function handleKeyboardSubmit() {
    errorMsg.value = "";
    const input = inputText.value.trim();

    // 无输入但有上次结果 → 直接复用结果
    if (!input && lastResultValue.value !== null) {
        return;
    }
    if (!input) return;

    // 有上次结果且输入以运算符开头 → 连算
    let expr = input;
    if (lastResultValue.value !== null && /^[+\-*/^%]/.test(input)) {
        expr = String(lastResultValue.value) + ' ' + input;
    }

    displayResult.value = null;

    try {
        const nums = [];
        // 包含逗号或换行 → 直接按分隔符处理
        if (/[,\n]/.test(expr)) {
            const tokens = expr.split(/[,\s\n]+/);
            for (const token of tokens) {
                if (!token) continue;
                nums.push(evaluateSingle(token));
            }
        } else {
            // 先尝试将整行作为一个表达式求值（如 "1 + 3"）
            try {
                nums.push(evaluateSingle(expr));
            } catch {
                // 整行求值失败，按空格分割逐个求值（如 "1 2 3"）
                const tokens = expr.split(/\s+/);
                for (const token of tokens) {
                    if (!token) continue;
                    nums.push(evaluateSingle(token));
                }
            }
        }
        if (nums.length === 0) {
            errorMsg.value = "未解析到有效的数字";
            return;
        }
        // 有上次结果且非运算符开头 → 多值输入将结果纳入数组首位
        if (lastResultValue.value !== null && !/^[+\-*/^%]/.test(input)) {
            if (/[,\n]/.test(input) || nums.length > 1) {
                nums.unshift(lastResultValue.value);
                expr = String(lastResultValue.value) + ', ' + input;
            }
        }
        numbers.value = nums;
        addHistory("键盘", expr, nums);
        lastInput.value = expr;
        // 屏幕显示总和
        const sum = nums.reduce((a, b) => a + b, 0);
        lastResultValue.value = nums.length > 1 ? sum : nums[0];
        displayResult.value = nums.length > 1 ? formatNum(sum) : formatNum(nums[0]);
        inputText.value = "";
    } catch (err) {
        errorMsg.value = err.message || String(err);
    }
}

function addHistory(source, input, nums) {
    history.value.unshift({
        id: Date.now(),
        source,
        input,
        nums,
        count: nums.length,
        sum: nums.reduce((a, b) => a + b, 0),
        avg: nums.reduce((a, b) => a + b, 0) / nums.length,
        time: new Date().toLocaleTimeString("zh-CN"),
    });
    if (history.value.length > 20) history.value.pop();
}

function formatNum(n) {
    return Number.isInteger(n) ? n.toString() : n.toFixed(4);
}
</script>

<template>
    <div class="page">
        <div class="drag-bar"></div>
        <div class="calc-dual">
            <!-- ====== 左侧：计算器 ====== -->
            <div class="calc-body" :class="{ 'panel-hidden': showStats }">
                <div class="calc-top-bar">
                    <span class="calc-brand">AnyCalculator</span>
                    <span class="calc-model">SC-100</span>
                </div>

                <div class="calc-screen">
                    <div class="screen-status">
                        <span class="status-mode">COMP</span>
                        <span v-if="stats" class="status-stat">STAT</span>
                        <span class="status-mem" v-if="history.length">M</span>
                        <span class="status-bat">▮▮▮</span>
                    </div>
                    <div class="screen-expr" :class="{ 'screen-hidden': !(displayResult && lastInput) }">
                        {{ lastInput || '\u00A0' }}
                    </div>
                    <div class="screen-input">
                        <input v-model="inputText" class="screen-input-field"
                            :placeholder="displayResult ? '' : '输入表达式，逗号/空格分隔多值...'"
                            @keydown.space.prevent="inputText += ' '" @keyup.enter="handleKeyboardSubmit" />
                    </div>
                    <div class="screen-output">
                        <div class="output-row">
                            <span v-show="displayResult" class="output-value">{{ displayResult }}<span v-if="resultUnit"
                                    class="output-unit"> {{ resultUnit }}</span></span>
                            <span v-show="!displayResult && previewResult" class="output-value dim">{{
                                previewResult?.value || '\u00A0' }}</span>
                            <span v-show="displayResult && paceText" class="output-pace" @click="showPace = !showPace"
                                title="点击切换配速显示">{{ paceText }}</span>
                        </div>
                        <span v-show="errorMsg" class="output-error">{{ errorMsg }}</span>
                    </div>
                    <div class="screen-stats" :class="{ 'screen-hidden': !stats }">
                        <span>n={{ stats?.count ?? '-' }}</span>
                        <span>Σ={{ stats ? formatNum(stats.sum) : '-' }}</span>
                        <span>x̄={{ stats ? formatNum(stats.avg) : '-' }}</span>
                        <span>σ={{ stats ? formatNum(stats.stddev) : '-' }}</span>
                        <span>min={{ stats ? formatNum(stats.min) : '-' }}</span>
                        <span>max={{ stats ? formatNum(stats.max) : '-' }}</span>
                    </div>
                </div>

                <div class="calc-hints-area">
                    <span v-for="h in functionHints" :key="h" class="hint-tag"
                        :class="{ 'hint-pace': paceHints.has(h) }" @click="insertHint(h)"
                        @mouseenter="showTooltip($event, hintTooltips[h] || h)" @mouseleave="hideTooltip">{{ h }}</span>
                </div>

                <div class="calc-keypad">
                    <div class="calc-grid">
                        <template v-for="row in calcKeys" :key="row.join('')">
                            <button v-for="key in row" :key="key" class="calc-btn" :class="{
                                'calc-num': key >= '0' && key <= '9' || key === '.',
                                'calc-op': ['÷', '×', '−', '+', '^', '%'].includes(key),
                                'calc-paren': key === '(' || key === ')',
                                'calc-del': key === '⌫',
                                'calc-pressed': activeKey === key,
                            }" @click="calcKeyTap(key)">{{ key }}</button>
                        </template>
                    </div>
                    <div class="calc-space-row">
                        <button class="calc-btn calc-space" :class="{ 'calc-pressed': activeKey === 'Space' }"
                            @click="calcKeyTap('Space')">SPACE</button>
                    </div>
                    <div class="calc-bottom-row" :class="{ 'has-detail': stats }">
                        <button class="calc-btn calc-clear" :class="{ 'calc-pressed': activeKey === 'AC' }"
                            @click="calcClear">AC</button>
                        <button class="calc-btn calc-equals" :class="{ 'calc-pressed': activeKey === '=' }"
                            @click="playClick(); handleKeyboardSubmit()">=</button>
                        <button v-if="stats" class="calc-btn calc-detail" @click="showStats = true">DETAIL</button>
                    </div>
                </div>
            </div>

            <!-- ====== 右侧：统计信息面板 ====== -->
            <div class="calc-info" :class="{ 'panel-hidden': !showStats }">
                <div class="info-top-bar">
                    <span class="info-brand">STAT</span>
                    <button class="info-back-btn" @click="showStats = false">← 返回</button>
                </div>
                <div class="info-lcd">
                    <div v-if="!stats && history.length === 0" class="info-empty">
                        <span class="info-empty-icon">📊</span>
                        <p>输入数据后将在此显示统计结果</p>
                    </div>

                    <div v-if="stats" class="info-stats">
                        <div class="info-title">统计结果</div>
                        <div class="info-grid">
                            <div class="info-item" @click="copyToClipboard(stats.count, 0)">
                                <span class="info-label">个数</span>
                                <span class="info-val">{{ stats.count }}</span>
                            </div>
                            <div class="info-item" @click="copyToClipboard(formatNum(stats.sum), 1)">
                                <span class="info-label">总和</span>
                                <span class="info-val">{{ formatNum(stats.sum) }}</span>
                            </div>
                            <div class="info-item" @click="copyToClipboard(formatNum(stats.avg), 4)">
                                <span class="info-label">平均值</span>
                                <span class="info-val">{{ formatNum(stats.avg) }}</span>
                            </div>
                            <div class="info-item" @click="copyToClipboard(formatNum(stats.median), 5)">
                                <span class="info-label">中位数</span>
                                <span class="info-val">{{ formatNum(stats.median) }}</span>
                            </div>
                            <div class="info-item" @click="copyToClipboard(formatNum(stats.stddev), 6)">
                                <span class="info-label">标准差</span>
                                <span class="info-val">{{ formatNum(stats.stddev) }}</span>
                            </div>
                            <div class="info-item" @click="copyToClipboard(formatNum(stats.max), 2)">
                                <span class="info-label">最大值</span>
                                <span class="info-val hi">{{ formatNum(stats.max) }}</span>
                            </div>
                            <div class="info-item" @click="copyToClipboard(formatNum(stats.min), 3)">
                                <span class="info-label">最小值</span>
                                <span class="info-val lo">{{ formatNum(stats.min) }}</span>
                            </div>
                            <div class="info-item" @click="copyToClipboard(formatNum(stats.range), 7)">
                                <span class="info-label">极差</span>
                                <span class="info-val">{{ formatNum(stats.range) }}</span>
                            </div>
                        </div>
                        <button class="info-clear-btn" @click="clearResults">清除结果</button>
                    </div>

                    <div class="info-grade" v-if="stats && rankedData.length > 0">
                        <div class="info-title" @click="showGrade = !showGrade" style="cursor:pointer">
                            等级评定 {{ showGrade ? '▾' : '▸' }}
                        </div>
                        <div v-show="showGrade">
                            <div class="grade-sliders">
                                <label>A/B <span>{{ aBound }}%</span></label>
                                <input type="range" min="0" max="100" v-model.number="aBound" />
                                <label>B/C <span>{{ bBound }}%</span></label>
                                <input type="range" min="0" max="100" v-model.number="bBound" />
                                <label>C/D <span>{{ cBound }}%</span></label>
                                <input type="range" min="0" max="100" v-model.number="cBound" />
                            </div>
                            <div class="grade-dist">
                                <span class="grade-badge a">A {{ gradeCounts.A }}</span>
                                <span class="grade-badge b">B {{ gradeCounts.B }}</span>
                                <span class="grade-badge c">C {{ gradeCounts.C }}</span>
                                <span class="grade-badge d">D {{ gradeCounts.D }}</span>
                            </div>
                            <div class="grade-table-wrap">
                                <table class="rank-table">
                                    <thead>
                                        <tr>
                                            <th @click="toggleGradeSort('rank')">#</th>
                                            <th @click="toggleGradeSort('raw')">值</th>
                                            <th @click="toggleGradeSort('pct')">%</th>
                                            <th @click="toggleGradeSort('grade')">等</th>
                                        </tr>
                                    </thead>
                                    <tbody>
                                        <tr v-for="r in sortedGradeData" :key="r.idx" :class="'grade-' + r.grade">
                                            <td class="col-rank">#{{ r.rank }}</td>
                                            <td>{{ formatNum(r.raw) }}</td>
                                            <td>{{ r.pct }}%</td>
                                            <td class="col-grade">{{ r.grade }}</td>
                                        </tr>
                                    </tbody>
                                </table>
                            </div>
                        </div>
                    </div>

                    <div v-if="history.length > 0" class="info-history">
                        <div class="info-title">历史记录</div>
                        <div class="history-list">
                            <div v-for="item in history" :key="item.id" class="history-item"
                                @click="fillFromHistory(item)">
                                <span class="history-input">{{ item.input }}</span>
                                <span class="history-result">{{ item.count }}个 · {{ formatNum(item.avg) }}</span>
                            </div>
                        </div>
                    </div>
                    <div class="info-back-bottom">
                        <button class="info-back-btn-bottom" @click="showStats = false">← 返回</button>
                    </div>
                </div>
            </div>
        </div>
        <!-- 全局 tooltip，绕过 overflow:hidden -->
        <div v-if="tooltip.show" class="global-tooltip" :style="{ left: tooltip.x + 'px', top: tooltip.y + 'px' }">
            {{ tooltip.text }}
        </div>
    </div>
</template>

<style scoped>
/* 窗口拖拽手柄 */
.calc-dual {
    display: flex;
    gap: 10px;
    align-items: stretch;
    max-width: 860px;
    width: 100%;
    height: calc(100dvh - env(safe-area-inset-top, 0px) - env(safe-area-inset-bottom, 0px));
    max-height: 880px;
    padding-top: 0px;
    position: relative;
}

/* 顶部拖拽条 */
.drag-bar {
    position: fixed;
    top: 0;
    left: 0;
    right: 0;
    height: 0px;
    -webkit-app-region: drag;
    z-index: 100;
}

.page {
    width: 100%;
    min-height: 100vh;
    min-height: 100dvh;
    background: transparent;
    /* padding: max(12px, env(safe-area-inset-top)) max(16px, env(safe-area-inset-right)) max(12px, env(safe-area-inset-bottom)) max(16px, env(safe-area-inset-left)); */
    display: flex;
    justify-content: center;
    align-items: flex-start;
}

/* ---- 顶部品牌栏 ---- */
.calc-top-bar {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 0 4px 10px;
}

.calc-body {
    flex: 1;
    max-width: 420px;
    background: #2d3436;
    border-radius: 18px;
    padding: 10px 10px 14px;
    box-shadow:
        0 8px 32px rgba(0, 0, 0, .35),
        0 2px 8px rgba(0, 0, 0, .2),
        inset 0 1px 0 rgba(255, 255, 255, .06);
    display: flex;
    flex-direction: column;
    overflow: hidden;
}

.calc-brand {
    font-size: 14px;
    font-weight: 800;
    color: #8b9094;
    letter-spacing: 2px;
    font-family: "Helvetica Neue", "PingFang SC", sans-serif;
}

.calc-model {
    font-size: 10px;
    color: #5a5f63;
    font-weight: 600;
}

.dark-toggle {
    background: none;
    border: 1px solid #4a5054;
    border-radius: 50%;
    width: 30px;
    height: 30px;
    font-size: 14px;
    cursor: pointer;
    display: flex;
    align-items: center;
    justify-content: center;
    transition: all .2s;
    color: #8b9094;
}

.dark-toggle:hover {
    background: #3d4347;
    border-color: #6c757d;
}

/* ---- LCD 显示屏 ---- */
.calc-screen {
    background: #d5d8dc;
    border: 3px solid #1a1c1d;
    border-radius: 6px;
    padding: 8px 12px 6px;
    margin-bottom: 6px;
    flex: 0 0 auto;
    display: flex;
    flex-direction: column;
    font-family: "Courier New", "SF Mono", "Fira Code", monospace;
    min-height: 0;
    max-height: 150px;
}

.screen-status {
    display: flex;
    gap: 8px;
    font-size: 9px;
    color: #6a7074;
    margin-bottom: 2px;
    letter-spacing: 1px;
}

.status-mode {
    flex: 1;
}

.status-stat {
    color: #4a5a8a;
    font-weight: 600;
}

.status-mem {
    color: #6a7074;
}

.status-bat {
    color: #5a6064;
    margin-left: auto;
}

.screen-expr {
    font-size: 11px;
    color: #6a7074;
    font-family: inherit;
    padding: 2px 0;
    text-align: right;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    min-height: 18px;
}

.screen-hidden {
    visibility: hidden;
}

.screen-input-field {
    width: 100%;
    background: none;
    border: none;
    outline: none;
    font-size: 18px;
    font-family: inherit;
    color: #1a1c1d;
    padding: 0;
    line-height: 1.3;
}

.screen-input-field::placeholder {
    color: #7a8085;
}

.screen-output {
    text-align: right;
    min-height: 32px;
    margin-top: 4px;
}

.output-row {
    display: flex;
    align-items: baseline;
    justify-content: flex-end;
    gap: 8px;
}

.output-value {
    font-size: 26px;
    font-weight: 800;
    color: #111;
}

.output-value.dim {
    color: #8a9094;
}

.output-unit {
    font-size: 14px;
    font-weight: 600;
    color: #8b9094;
    margin-left: 2px;
}

.output-pace {
    font-size: 14px;
    font-weight: 700;
    color: #f6851b;
    background: #fff5ee;
    padding: 2px 8px;
    border-radius: 4px;
    cursor: pointer;
    user-select: none;
    transition: all .15s;
    white-space: nowrap;
}

.output-pace:hover {
    background: #ffe8d6;
    color: #e07510;
}

.output-error {
    font-size: 12px;
    color: #4a5054;
    font-family: "Courier New", "SF Mono", "Fira Code", monospace;
}

.screen-stats {
    display: flex;
    flex-wrap: wrap;
    gap: 4px 10px;
    font-size: 9px;
    color: #5a6064;
    margin-top: 6px;
    letter-spacing: .3px;
    padding-top: 4px;
    border-top: 1px solid #c0c4c8;
    min-height: 22px;
}

/* ---- 预设函数矩阵 ---- */
.calc-hints-area {
    display: grid;
    grid-template-columns: repeat(5, 1fr);
    gap: 3px;
    margin-bottom: 6px;
    padding: 0 2px;
    overflow: visible;
    z-index: 5;
    flex-shrink: 0;
}

.hint-tag {
    position: relative;
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 9px 2px;
    font-size: 11px;
    overflow: visible;
    text-overflow: ellipsis;
    background: linear-gradient(180deg, #4a5054 0%, #3d4347 40%, #303538 100%);
    border: 1px solid #353a3e;
    border-radius: 4px;
    color: #c8cdd0;
    cursor: pointer;
    transition: all .1s;
    font-family: "Courier New", "SF Mono", "Fira Code", monospace;
    font-weight: 600;
    letter-spacing: 0.3px;
    text-align: center;
    white-space: nowrap;
    box-shadow:
        0 3px 0 #5a6068,
        0 4px 8px rgba(0, 0, 0, .2),
        inset 0 1px 1px rgba(255, 255, 255, .1),
        inset 0 -1px 2px rgba(0, 0, 0, .15);
}

.hint-tag:hover {
    filter: brightness(1.15);
    border-color: #5a6068;
    z-index: 20;
}

.hint-tag:active {
    filter: brightness(.9);
    transform: translateY(2px);
    box-shadow:
        0 1px 0 #5a6068,
        0 2px 4px rgba(0, 0, 0, .15),
        inset 0 1px 1px rgba(255, 255, 255, .08);
}

/* 配速按钮：橙色高亮 */
.hint-pace {
    background: linear-gradient(180deg, #5a4530 0%, #4a3825 40%, #3d3028 100%);
    border-color: #8b6914;
    color: #f5c842;
    box-shadow:
        0 3px 0 #7a6040,
        0 4px 8px rgba(0, 0, 0, .2),
        inset 0 1px 1px rgba(255, 200, 60, .15),
        inset 0 -1px 2px rgba(0, 0, 0, .15);
}

.hint-pace:hover {
    filter: brightness(1.2);
    border-color: #c5951a;
    color: #fad84a;
}

.hint-pace:active {
    filter: brightness(.9);
    transform: translateY(2px);
    box-shadow:
        0 1px 0 #7a6040,
        0 2px 4px rgba(0, 0, 0, .15);
}

/* 自定义 tooltip */
.hint-tag::after,
.hint-tag::before {
    display: none;
}

/* 全局 tooltip（固定定位，不受 overflow 影响）*/
.global-tooltip {
    position: fixed;
    transform: translateX(-50%);
    padding: 4px 10px;
    background: #1a1a2e;
    color: #fff;
    font-size: 11px;
    font-family: -apple-system, "PingFang SC", "Microsoft YaHei", sans-serif;
    white-space: nowrap;
    border-radius: 4px;
    pointer-events: none;
    z-index: 9999;
}

.hint-text {
    font-size: 12px;
    color: #999;
    margin-bottom: 10px;
}

.hint-text code {
    background: #f5f3ff;
    padding: 1px 5px;
    border-radius: 3px;
    font-size: 11px;
    color: #6366f1;
}

.input-row {
    display: flex;
    gap: 8px;
}

.text-input {
    flex: 1;
    padding: 10px 14px;
    background: #f8f9fa;
    border: 1.5px solid #e5e7eb;
    border-radius: 8px;
    color: #1a1a2e;
    font-size: 14px;
    outline: none;
    transition: border-color .2s;
}

.text-input:focus {
    border-color: #6366f1;
}

.text-input::placeholder {
    color: #bbb;
}

/* File drop zone */
.file-drop-zone {
    flex: 1;
    padding: 10px 14px;
    background: #f8f9fa;
    border: 1.5px dashed #ddd;
    border-radius: 8px;
    color: #333;
    font-size: 13px;
    cursor: pointer;
    transition: all .2s;
    display: flex;
    align-items: center;
    min-height: 42px;
}

.file-drop-zone:hover {
    border-color: #6366f1;
    background: #f5f3ff;
}

.file-placeholder {
    color: #bbb;
}

.file-selected {
    color: #6366f1;
    font-weight: 500;
}

.action-btn {
    padding: 10px 20px;
    border: none;
    border-radius: 8px;
    font-size: 13px;
    font-weight: 600;
    cursor: pointer;
    transition: all .2s;
    white-space: nowrap;
}

.action-btn.primary {
    background: #6366f1;
    color: #fff;
}

.action-btn.primary:hover:not(:disabled) {
    background: #5558e6;
}

.action-btn.primary:disabled {
    opacity: .35;
    cursor: not-allowed;
}

.action-btn.small {
    padding: 4px 10px;
    font-size: 11px;
    background: #f5f5f5;
    color: #999;
    border-radius: 5px;
}

.action-btn.small:hover {
    background: #eee;
    color: #666;
}

.error-msg {
    margin-top: 8px;
    padding: 8px 12px;
    background: #fef2f2;
    border: 1px solid #fecaca;
    border-radius: 6px;
    color: #dc2626;
    font-size: 12px;
}

.preview-result {
    margin-top: 6px;
    padding: 6px 12px;
    background: #f0fdf4;
    border: 1px solid #bbf7d0;
    border-radius: 6px;
    color: #16a34a;
    font-size: 13px;
    font-family: "SF Mono", "Fira Code", monospace;
    font-weight: 600;
}

.copy-hint {
    position: absolute;
    top: 4px;
    right: 6px;
    font-size: 10px;
    opacity: 0.5;
    transition: opacity .15s;
}

.stat-card:hover .copy-hint {
    opacity: 1;
}

/* Results */
.results {
    margin-top: 24px;
    animation: fadeIn .3s ease;
}

.results-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 12px;
}

.results-header h2 {
    font-size: 15px;
    font-weight: 600;
    color: #1a1a2e;
}

.stats-grid {
    display: grid;
    grid-template-columns: repeat(4, 1fr);
    gap: 8px;
}

.stat-card {
    background: #f8f9fa;
    border-radius: 8px;
    padding: 12px 8px;
    text-align: center;
    position: relative;
    cursor: pointer;
    user-select: none;
    transition: background .15s;
}

.stat-card:hover {
    background: #eef2ff;
}

.stat-label {
    display: block;
    font-size: 10px;
    color: #999;
    margin-bottom: 4px;
    letter-spacing: .5px;
}

.stat-value {
    font-size: 16px;
    font-weight: 700;
    font-family: "SF Mono", "Fira Code", monospace;
    color: #1a1a2e;
}

.highlight-max {
    color: #16a34a;
}

.highlight-min {
    color: #dc2626;
}

/* Rank table */
.rank-table-wrap {
    margin-top: 14px;
    max-height: 220px;
    overflow-y: auto;
    border: 1px solid #f0f0f0;
    border-radius: 8px;
}

.rank-table {
    width: 100%;
    border-collapse: collapse;
    font-size: 12px;
    font-family: "SF Mono", "Fira Code", monospace;
}

.rank-table thead {
    position: sticky;
    top: 0;
    z-index: 1;
}

.rank-table th {
    background: #f8f9fa;
    color: #999;
    font-weight: 500;
    padding: 6px 10px;
    text-align: center;
    border-bottom: 1px solid #eee;
    font-size: 11px;
}

.rank-table th.sortable {
    cursor: pointer;
    user-select: none;
    transition: color .15s;
}

.rank-table th.sortable:hover {
    color: #6366f1;
}

.sort-arrow {
    font-size: 9px;
    color: #6366f1;
}

.rank-table td {
    padding: 5px 10px;
    text-align: center;
    border-bottom: 1px solid #f5f5f5;
    color: #555;
}

.rank-table tbody tr:hover {
    background: #f8f9ff;
}

.col-idx {
    color: #bbb;
    width: 20%;
}

.col-val {
    width: 30%;
}

.col-rank {
    color: #6366f1;
    font-weight: 600;
    width: 20%;
}

.col-pct {
    color: #16a34a;
    font-weight: 500;
    width: 20%;
}

.dark .grade-header {
    color: #e2e8f0;
}

.dark .grade-section {
    border-color: #2d3748;
}

.dark .grade-sliders {
    color: #7c7f93;
}

.dark .grade-table-wrap {
    border-color: #2d3748;
}

/* Grade toggle */
.grade-toggle {
    position: relative;
    display: flex;
    align-items: center;
    gap: 6px;
    margin-top: 16px;
    font-size: 13px;
    color: #6366f1;
    cursor: pointer;
    user-select: none;
}

.grade-toggle input[type=checkbox] {
    accent-color: #6366f1;
    cursor: pointer;
}

/* 等级评定 tooltip */
.grade-toggle::after {
    content: attr(data-tooltip);
    position: absolute;
    bottom: calc(100% + 6px);
    left: 0;
    padding: 4px 10px;
    background: #1a1a2e;
    color: #fff;
    font-size: 11px;
    font-family: -apple-system, "PingFang SC", "Microsoft YaHei", sans-serif;
    white-space: nowrap;
    border-radius: 4px;
    pointer-events: none;
    opacity: 0;
    transition: opacity .15s;
    z-index: 20;
}

.grade-toggle::before {
    content: "";
    position: absolute;
    bottom: calc(100% + 1px);
    left: 20px;
    border: 5px solid transparent;
    border-top-color: #1a1a2e;
    pointer-events: none;
    opacity: 0;
    transition: opacity .15s;
    z-index: 20;
}

.grade-toggle:hover::after,
.grade-toggle:hover::before {
    opacity: 1;
}

.grade-hint {
    margin-top: 6px;
    font-size: 11px;
    color: #999;
    line-height: 1.4;
}

/* Grade section */
.grade-section {
    margin-top: 18px;
    border-top: 1px solid #f0f0f0;
    padding-top: 14px;
}

.grade-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 10px;
    font-size: 13px;
    font-weight: 600;
    color: #1a1a2e;
}

.grade-header-right {
    display: flex;
    align-items: center;
    gap: 8px;
}

.copy-table-btn {
    padding: 3px 10px;
    border: 1px solid #e8e5ff;
    border-radius: 5px;
    background: #f5f3ff;
    color: #6366f1;
    font-size: 11px;
    cursor: pointer;
    white-space: nowrap;
    transition: all .15s;
}

.copy-table-btn:hover {
    background: #ede9fe;
    border-color: #6366f1;
}

.grade-dist {
    display: flex;
    gap: 6px;
}

.grade-badge {
    font-size: 11px;
    padding: 2px 8px;
    border-radius: 4px;
    font-weight: 600;
}

.grade-badge.a {
    background: #dcfce7;
    color: #16a34a;
}

.grade-badge.b {
    background: #dbeafe;
    color: #2563eb;
}

.grade-badge.c {
    background: #fef3c7;
    color: #d97706;
}

.grade-badge.d {
    background: #fee2e2;
    color: #dc2626;
}

.grade-sliders {
    display: grid;
    grid-template-columns: auto 1fr;
    gap: 4px 10px;
    margin-bottom: 12px;
    font-size: 11px;
    color: #999;
    align-items: center;
}

.grade-sliders label span {
    font-weight: 600;
    color: #6366f1;
    margin-left: 4px;
}

.grade-sliders input[type=range] {
    width: 100%;
    accent-color: #6366f1;
    height: 4px;
}

.grade-table-wrap {
    max-height: 200px;
    overflow-y: auto;
    border: 1px solid #f0f0f0;
    border-radius: 8px;
}

.col-grade {
    font-weight: 700;
    width: 18%;
}

tr.grade-A .col-grade {
    color: #16a34a;
}

tr.grade-B .col-grade {
    color: #2563eb;
}

tr.grade-C .col-grade {
    color: #d97706;
}

tr.grade-D .col-grade {
    color: #dc2626;
}

/* Dark grade */
.dark .grade-header {
    color: #e2e8f0;
}

.dark .grade-section {
    border-color: #2d3748;
}

.dark .grade-sliders {
    color: #7c7f93;
}

.dark .grade-table-wrap {
    border-color: #2d3748;
}

.dark .grade-toggle::after {
    background: #e2e8f0;
    color: #1a1a2e;
}

.dark .grade-toggle::before {
    border-top-color: #e2e8f0;
}

.dark .grade-hint {
    color: #5a5d73;
}

.dark .copy-table-btn {
    background: #1e293b;
    border-color: #334155;
    color: #818cf8;
}

.dark .copy-table-btn:hover {
    background: #312e81;
    border-color: #818cf8;
}

.dark .grade-badge.a {
    background: #14532d;
    color: #86efac;
}

.dark .grade-badge.b {
    background: #1e3a5f;
    color: #93c5fd;
}

.dark .grade-badge.c {
    background: #5c3d0e;
    color: #fcd34d;
}

.dark .grade-badge.d {
    background: #3b1016;
    color: #fca5a5;
}

.number-list {
    margin-top: 12px;
}

.number-list summary {
    cursor: pointer;
    font-size: 12px;
    color: #999;
    padding: 6px 0;
}

.number-tags {
    display: flex;
    flex-wrap: wrap;
    gap: 4px;
    margin-top: 6px;
}

.number-tag {
    padding: 2px 8px;
    background: #f5f5f5;
    border-radius: 4px;
    font-size: 12px;
    font-family: "SF Mono", "Fira Code", monospace;
    color: #666;
}

/* History */
.history {
    margin-top: 20px;
    border-top: 1px solid #f0f0f0;
    padding-top: 16px;
}

.history h3 {
    font-size: 13px;
    margin-bottom: 10px;
    color: #999;
    font-weight: 500;
}

.history-list {
    display: flex;
    flex-direction: column;
    gap: 4px;
    max-height: 180px;
    overflow-y: auto;
}

.history-item {
    display: flex;
    align-items: center;
    gap: 6px;
    padding: 6px 10px;
    background: #fafafa;
    border-radius: 6px;
    font-size: 11px;
}

.history-source {
    font-size: 14px;
}

.history-input {
    flex: 1;
    color: #555;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
}

.history-result {
    color: #6366f1;
    font-weight: 600;
    white-space: nowrap;
}

.history-time {
    color: #bbb;
    font-size: 10px;
}

/* Dark mode toggle */
.dark-toggle {
    position: absolute;
    top: 12px;
    right: 16px;
    background: none;
    border: 1px solid #e5e7eb;
    border-radius: 50%;
    width: 34px;
    height: 34px;
    font-size: 16px;
    cursor: pointer;
    display: flex;
    align-items: center;
    justify-content: center;
    transition: all .2s;
}

.dark-toggle:hover {
    background: #f3f4f6;
}

/* Paste mode */
.input-col {
    display: flex;
    flex-direction: column;
    gap: 8px;
}

.paste-textarea {
    width: 100%;
    padding: 10px 14px;
    background: #f8f9fa;
    border: 1.5px solid #e5e7eb;
    border-radius: 8px;
    color: #1a1a2e;
    font-size: 13px;
    font-family: "SF Mono", "Fira Code", monospace;
    outline: none;
    resize: vertical;
    transition: border-color .2s;
}

.paste-textarea:focus {
    border-color: #6366f1;
}

.paste-textarea::placeholder {
    color: #bbb;
}

/* History item cursor */
.history-item {
    cursor: pointer;
    transition: background .15s;
}

.history-item:hover {
    background: #f0f0f0;
}

/* ====== 深色模式（已移除，使用默认 Casio 主题）====== */


/* ====== 右侧：彩色 LCD 统计面板 ====== */
.calc-info {
    flex: 1;
    max-width: 420px;
    background: #2d3436;
    border-radius: 18px;
    padding: 10px 10px 14px;
    box-shadow:
        0 8px 32px rgba(0, 0, 0, .35),
        0 2px 8px rgba(0, 0, 0, .2),
        inset 0 1px 0 rgba(255, 255, 255, .06);
    display: flex;
    flex-direction: column;
    overflow: hidden;
}

.info-top-bar {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 0 4px 8px;
}

.info-brand {
    font-size: 12px;
    font-weight: 800;
    color: #8b9094;
    letter-spacing: 2px;
    font-family: "Helvetica Neue", "PingFang SC", sans-serif;
}

.info-back-btn {
    background: none;
    border: 1px solid #4a5054;
    border-radius: 4px;
    color: #8b9094;
    font-size: 10px;
    padding: 3px 10px;
    cursor: pointer;
    transition: all .15s;
}

.info-back-btn:hover {
    background: #3d4347;
    color: #c0c4c8;
}

.info-back-bottom {
    position: absolute;
    bottom: 8px;
    right: 12px;
    display: flex;
}

.info-back-btn-bottom {
    background: #4a5054;
    border: none;
    border-radius: 5px;
    color: #fff;
    font-size: 12px;
    font-weight: 600;
    padding: 8px 22px;
    cursor: pointer;
    transition: all .15s;
}

.info-back-btn-bottom:hover {
    background: #636b72;
}

.info-back-btn-bottom:active {
    background: #353a3e;
    transform: translateY(1px);
}

.info-lcd {
    flex: 1;
    background: #d5d8dc;
    border: 3px solid #1a1c1d;
    border-radius: 6px;
    padding: 10px 12px;
    overflow: hidden;
    font-size: 12px;
    color: #333;
    min-height: 0;
    position: relative;
}

.info-empty {
    flex: 1;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    color: #5a5f63;
    text-align: center;
}

.info-empty-icon {
    font-size: 48px;
    display: block;
    margin-bottom: 12px;
    opacity: .5;
}

.info-title {
    font-size: 11px;
    font-weight: 700;
    color: #8b9094;
    margin-bottom: 10px;
    padding-bottom: 6px;
    border-bottom: 1px solid #3d4347;
    letter-spacing: 2px;
    text-transform: uppercase;
}

.info-stats,
.info-grade,
.info-history {
    margin-bottom: 18px;
}

.info-grid {
    display: grid;
    grid-template-columns: repeat(4, 1fr);
    gap: 5px;
}

.info-item {
    background: transparent;
    border: 1px solid #c0c4c8;
    border-radius: 5px;
    padding: 7px 3px;
    text-align: center;
    cursor: pointer;
    transition: all .15s;
}

.info-item:hover {
    background: #c8ccd0;
    border-color: #a0a8ac;
}

.info-label {
    display: block;
    font-size: 10px;
    color: #8a9094;
    margin-bottom: 2px;
    letter-spacing: .5px;
}

.info-val {
    font-size: 13px;
    font-weight: 700;
    font-family: "SF Mono", "Fira Code", monospace;
    color: #2a2e30;
}

.info-val.hi {
    color: #2d7a3a;
}

.info-val.lo {
    color: #b03030;
}

.info-clear-btn {
    width: 100%;
    margin-top: 6px;
    padding: 6px;
    border: 1px solid #c0c4c8;
    border-radius: 5px;
    background: transparent;
    color: #8a9094;
    font-size: 10px;
    cursor: pointer;
    transition: all .15s;
}

.info-clear-btn:hover {
    background: #f0d0d4;
    border-color: #d0a0a4;
    color: #b03030;
}

/* 右侧等级评定 */
.info-grade .grade-dist {
    display: flex;
    gap: 4px;
    margin-bottom: 8px;
}

.info-grade .grade-badge {
    font-size: 10px;
    padding: 3px 10px;
    border-radius: 6px;
    font-weight: 600;
}

.grade-badge.a {
    background: #dcfce7;
    color: #16a34a;
}

.grade-badge.b {
    background: #dbeafe;
    color: #2563eb;
}

.grade-badge.c {
    background: #fef3c7;
    color: #d97706;
}

.grade-badge.d {
    background: #fee2e2;
    color: #dc2626;
}

.info-grade .grade-sliders {
    display: grid;
    grid-template-columns: auto 1fr;
    gap: 2px 8px;
    margin-bottom: 8px;
    font-size: 10px;
    color: #6a7074;
    align-items: center;
}

.info-grade .grade-sliders label span {
    font-weight: 600;
    color: #6366f1;
}

.info-grade .grade-sliders input[type=range] {
    width: 100%;
    accent-color: #6366f1;
    height: 3px;
}

.info-grade .grade-table-wrap {
    max-height: 160px;
    overflow-y: auto;
    border: 1px solid #d0d5d8;
    border-radius: 6px;
}

.info-grade .rank-table {
    width: 100%;
    border-collapse: collapse;
    font-size: 11px;
    font-family: "SF Mono", "Fira Code", monospace;
}

.info-grade .rank-table th {
    background: transparent;
    color: #5a6064;
    font-weight: 600;
    padding: 4px 6px;
    text-align: center;
    border-bottom: 1px solid #c0c4c8;
    font-size: 9px;
    cursor: pointer;
    user-select: none;
    letter-spacing: 1px;
}

.info-grade .rank-table td {
    padding: 3px 6px;
    text-align: center;
    border-bottom: 1px solid #d8dbde;
    color: #4a5054;
}

.info-grade .rank-table tbody tr:hover {
    background: #f5f6f7;
}

.info-grade .col-rank {
    color: #6366f1;
    font-weight: 600;
}

.info-grade .col-grade {
    font-weight: 700;
}

.info-grade tr.grade-A .col-grade {
    color: #16a34a;
}

.info-grade tr.grade-B .col-grade {
    color: #2563eb;
}

.info-grade tr.grade-C .col-grade {
    color: #d97706;
}

.info-grade tr.grade-D .col-grade {
    color: #dc2626;
}

/* 右侧历史记录 */
.info-history .history-list {
    display: flex;
    flex-direction: column;
    gap: 3px;
    max-height: 180px;
    overflow-y: auto;
}

.info-history .history-item {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 5px 8px;
    background: transparent;
    border: 1px solid #c0c4c8;
    border-radius: 5px;
    font-size: 10px;
    cursor: pointer;
    transition: all .15s;
}

.info-history .history-item:hover {
    background: #c8ccd0;
}

.info-history .history-input {
    color: #4a5054;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    flex: 1;
}

.info-history .history-result {
    color: #4a5a8a;
    font-weight: 600;
    white-space: nowrap;
    margin-left: 8px;
}

/* ====== 响应式：移动端单屏滑动 ====== */
@media (max-width: 600px) {
    .calc-dual {
        flex-direction: row;
        overflow-x: auto;
        scroll-snap-type: x mandatory;
        gap: 0;
        height: calc(100dvh - env(safe-area-inset-top, 0px) - env(safe-area-inset-bottom, 0px));
    }

    .calc-body,
    .calc-info {
        flex: 0 0 100%;
        max-width: none;
        scroll-snap-align: start;
        height: 100%;
        border-radius: 18px;
    }

    .panel-hidden {
        display: none;
    }

    /* 滑动提示 */
    .swipe-hint {
        display: flex;
        justify-content: center;
        gap: 8px;
        padding: 8px 0 0;
    }

    .swipe-dot {
        width: 6px;
        height: 6px;
        border-radius: 50%;
        background: #c0c4c8;
    }

    .swipe-dot.active {
        background: #4a5054;
        width: 18px;
        border-radius: 3px;
    }
}

@keyframes fadeIn {
    from {
        opacity: 0;
        transform: translateY(6px);
    }

    to {
        opacity: 1;
        transform: translateY(0);
    }
}

/* ====== 主键盘 Casio 按键 ====== */
.calc-keypad {
    margin-top: 2px;
    flex-shrink: 0;
    padding-bottom: 6px;
}

.calc-grid {
    display: grid;
    grid-template-columns: repeat(4, 1fr);
    row-gap: 8px;
    column-gap: 8px;
    margin-bottom: 5px;
}

.calc-bottom-row {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 5px;
}

.calc-bottom-row.has-detail {
    grid-template-columns: 1fr 1fr 1fr;
}

/* ===== 通用按键 ===== */
.calc-btn {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 100%;
    border: none;
    border-radius: 5px;
    font-size: 1rem;
    font-weight: 600;
    font-family: "Helvetica Neue", "PingFang SC", "Microsoft YaHei", sans-serif;
    cursor: pointer;
    outline: none;
    transition: filter .1s, transform .1s;
    -webkit-tap-highlight-color: transparent;
    touch-action: manipulation;
    user-select: none;
    padding: 10px 4px;
    line-height: 1;
    box-shadow:
        0 4px 0 rgba(0, 0, 0, .18),
        0 6px 10px rgba(0, 0, 0, .12),
        inset 0 1px 2px rgba(255, 255, 255, .2),
        inset 0 -1px 3px rgba(0, 0, 0, .06);
}

.calc-btn:hover {
    filter: brightness(1.06);
}

.calc-btn:active {
    filter: brightness(.85);
    transform: translateY(3px);
    box-shadow:
        0 1px 0 rgba(0, 0, 0, .15),
        0 2px 4px rgba(0, 0, 0, .1),
        inset 0 1px 1px rgba(255, 255, 255, .1);
}

.calc-btn.calc-num {
    background: linear-gradient(180deg, #fafaf5 0%, #f0f0ea 40%, #e0e0d8 100%);
    color: #1a1a1a;
    font-size: 1.1rem;
    font-weight: 700;
    box-shadow:
        0 4px 0 #c5c5bb,
        0 6px 10px rgba(0, 0, 0, .1),
        inset 0 1px 2px rgba(255, 255, 255, .4),
        inset 0 -1px 3px rgba(0, 0, 0, .05);
}

.calc-btn.calc-num:active {
    box-shadow:
        0 1px 0 #c5c5bb,
        0 2px 4px rgba(0, 0, 0, .08);
}

.calc-btn.calc-op {
    background: linear-gradient(180deg, #5a6068 0%, #4a5054 40%, #3a3f42 100%);
    color: #fff;
    font-size: 1.05rem;
    font-weight: 700;
    box-shadow:
        0 4px 0 #6a7278,
        0 6px 10px rgba(0, 0, 0, .2),
        inset 0 1px 2px rgba(255, 255, 255, .12),
        inset 0 -1px 3px rgba(0, 0, 0, .1);
}

.calc-btn.calc-op:active {
    box-shadow:
        0 1px 0 #6a7278,
        0 2px 4px rgba(0, 0, 0, .15);
}

.calc-btn.calc-paren {
    background: linear-gradient(180deg, #e5e5df 0%, #d5d5cf 40%, #c5c5bd 100%);
    color: #1a1a1a;
    font-size: 1rem;
    font-weight: 700;
    box-shadow:
        0 4px 0 #a5a59b,
        0 6px 10px rgba(0, 0, 0, .1),
        inset 0 1px 2px rgba(255, 255, 255, .4),
        inset 0 -1px 3px rgba(0, 0, 0, .05);
}

.calc-btn.calc-paren:active {
    box-shadow:
        0 1px 0 #a5a59b,
        0 2px 4px rgba(0, 0, 0, .08);
}

.calc-btn.calc-del {
    background: linear-gradient(180deg, #e5e5df 0%, #d5d5cf 40%, #c5c5bd 100%);
    color: #444;
    font-size: .95rem;
    font-weight: 600;
    box-shadow:
        0 4px 0 #a5a59b,
        0 6px 10px rgba(0, 0, 0, .1),
        inset 0 1px 2px rgba(255, 255, 255, .4),
        inset 0 -1px 3px rgba(0, 0, 0, .05);
}

.calc-btn.calc-del:active {
    box-shadow:
        0 1px 0 #a5a59b,
        0 2px 4px rgba(0, 0, 0, .08);
}

.calc-space-row {
    margin-top: 10px;
    margin-bottom: 10px;
}

.calc-btn.calc-space {
    width: 100%;
    border-radius: 5px;
    background: linear-gradient(180deg, #6da0cc 0%, #5b8cb8 40%, #4a78a0 100%);
    color: #e8f0f8;
    font-size: .75rem;
    font-weight: 600;
    padding: 14px 4px;
    letter-spacing: 2px;
    box-shadow:
        0 4px 0 #7db0d8,
        0 6px 10px rgba(0, 0, 0, .15),
        inset 0 1px 2px rgba(255, 255, 255, .2),
        inset 0 -1px 3px rgba(0, 0, 0, .08);
}

.calc-btn.calc-space:active {
    box-shadow:
        0 1px 0 #7db0d8,
        0 2px 4px rgba(0, 0, 0, .1);
}

.calc-btn.calc-clear {
    background: linear-gradient(180deg, #5a6068 0%, #4a5054 40%, #3a3f42 100%);
    color: #fff;
    font-size: 1rem;
    font-weight: 700;
    border-radius: 5px;
    padding: 11px 4px;
    box-shadow:
        0 4px 0 #6a7278,
        0 6px 10px rgba(0, 0, 0, .2),
        inset 0 1px 2px rgba(255, 255, 255, .12),
        inset 0 -1px 3px rgba(0, 0, 0, .1);
}

.calc-btn.calc-clear:active {
    box-shadow:
        0 1px 0 #6a7278,
        0 2px 4px rgba(0, 0, 0, .15);
}

.calc-btn.calc-equals {
    background: linear-gradient(180deg, #ffb84d 0%, #ff9a2e 25%, #f6851b 50%, #e07510 100%);
    color: #fff;
    font-size: 1.2rem;
    font-weight: 700;
    border-radius: 6px;
    padding: 11px 4px;
    box-shadow:
        0 4px 0 #ffcc66,
        0 8px 16px rgba(0, 0, 0, .3),
        inset 0 2px 3px rgba(255, 255, 255, .35),
        inset 0 -2px 4px rgba(0, 0, 0, .1);
}

.calc-btn.calc-equals:active {
    box-shadow:
        0 1px 0 #ffcc66,
        0 3px 6px rgba(0, 0, 0, .25),
        inset 0 1px 2px rgba(255, 255, 255, .2),
        inset 0 -1px 2px rgba(0, 0, 0, .05);
    transform: translateY(3px);
}

.calc-btn.calc-detail {
    background: linear-gradient(180deg, #6a7582 0%, #5a6570 40%, #4a5560 100%);
    color: #fff;
    font-size: .8rem;
    font-weight: 700;
    border-radius: 5px;
    padding: 11px 4px;
    box-shadow:
        0 4px 0 #7a8592,
        0 6px 10px rgba(0, 0, 0, .2),
        inset 0 1px 2px rgba(255, 255, 255, .12),
        inset 0 -1px 3px rgba(0, 0, 0, .1);
}

.calc-btn.calc-detail:active {
    box-shadow:
        0 1px 0 #7a8592,
        0 2px 4px rgba(0, 0, 0, .15);
}

/* 键盘/触控按下反馈 */
.calc-btn.calc-pressed {
    filter: brightness(.7);
    transform: translateY(2px);
    box-shadow: 0 0 0 rgba(0, 0, 0, .1);
}

.calc-btn.calc-detail:active {
    filter: brightness(.82);
    transform: translateY(1px);
    box-shadow: 0 1px 0 rgba(0, 0, 0, .15);
}
</style>
