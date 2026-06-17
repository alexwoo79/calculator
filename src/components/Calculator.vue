<script setup>
import { ref, computed, onMounted, onUnmounted, nextTick } from "vue";

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

// ===== 功能模式 =====
const calcMode = ref('standard');  // 'standard' | 'solve'
const useDegrees = ref(false);     // false=弧度, true=角度
const useInverse = ref(false);     // false=正函数, true=反函数

// ===== LCD 拖拽滚动 =====
const outputRow = ref(null);
let dragStartX = 0;
let dragScrollLeft = 0;
let isDragging = false;

function startDragScroll(e) {
    const el = outputRow.value;
    if (!el || el.scrollWidth <= el.clientWidth) return;
    isDragging = true;
    const clientX = e.touches ? e.touches[0].clientX : e.clientX;
    dragStartX = clientX;
    dragScrollLeft = el.scrollLeft;
    el.style.cursor = 'grabbing';
    el.style.userSelect = 'none';
}

function dragScroll(e) {
    if (!isDragging) return;
    const el = outputRow.value;
    if (!el) return;
    const clientX = e.touches ? e.touches[0].clientX : e.clientX;
    const dx = clientX - dragStartX;
    el.scrollLeft = dragScrollLeft - dx;
}

function stopDragScroll() {
    if (!isDragging) return;
    isDragging = false;
    const el = outputRow.value;
    if (el) {
        el.style.cursor = '';
        el.style.userSelect = '';
    }
}

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
    const isInputFocused = document.activeElement?.tagName === 'INPUT';

    // 左右方向键切换面板（输入框聚焦时不拦截）
    if (e.key === 'ArrowLeft' || e.key === 'ArrowRight') {
        if (!isInputFocused) {
            e.preventDefault();
            showStats.value = e.key === 'ArrowRight';
        }
        return;
    }

    const mapped = keyMap[e.key];
    if (!mapped) return;

    const input = document.activeElement;
    const isOurInput = isInputFocused && input?.closest('.calc-screen');

    // AC 全局处理
    if (mapped === 'AC') {
        e.preventDefault();
        activeKey.value = mapped;
        playClick();
        calcClear();
        return;
    }

    // 退格：在输入框内用光标位置精确删除
    if (mapped === '⌫') {
        e.preventDefault();
        activeKey.value = mapped;
        playClick();
        if (isOurInput && input.selectionStart !== undefined) {
            const pos = input.selectionStart;
            if (pos > 0) {
                const before = inputText.value.slice(0, pos - 1);
                const after = inputText.value.slice(pos);
                inputText.value = before + after;
                // 恢复光标位置
                nextTick(() => {
                    input.setSelectionRange(pos - 1, pos - 1);
                });
            }
        } else {
            inputText.value = inputText.value.slice(0, -1);
        }
        return;
    }

    // SPACE
    if (mapped === 'Space') {
        e.preventDefault();
        activeKey.value = mapped;
        playClick();
        inputText.value += ' ';
        return;
    }

    // = 键
    if (mapped === '=') {
        e.preventDefault();
        activeKey.value = mapped;
        playClick();
        if (calcMode.value === 'solve' && !inputText.value.includes('=')) {
            inputText.value += '=';
        } else {
            handleKeyboardSubmit();
        }
        return;
    }

    // 输入框聚焦时，普通字符由浏览器自然输入（避免双重输入）
    if (isOurInput) {
        activeKey.value = mapped;
        playClick();
        // 只阻止空格（已在上面处理），其余字符交给浏览器
        return;
    }

    // 输入框未聚焦：手动插入（模拟计算器键盘输入）
    e.preventDefault();
    activeKey.value = mapped;
    playClick();
    inputText.value += mapped === '÷' ? '/' : mapped === '×' ? '*' : mapped === '−' ? '-' : mapped;
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
        const input = document.querySelector('.screen-input-field');
        if (input && input.selectionStart !== undefined && input.selectionStart > 0) {
            const pos = input.selectionStart;
            const before = inputText.value.slice(0, pos - 1);
            const after = inputText.value.slice(pos);
            inputText.value = before + after;
            nextTick(() => input.setSelectionRange(pos - 1, pos - 1));
        } else {
            inputText.value = inputText.value.slice(0, -1);
        }
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
    "pi", "e", "1/x", "x^2", "x^3", "km", "Hour", "Min", "Second",
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
    "1/x": "倒数", "x^2": "平方", "x^3": "立方",
    "km": "千米 (=1) · 距离单位", "Hour": "小时 (=1) · 时间单位",
    "Min": "分钟 (=1/60h) · 时间单位", "Second": "秒 (=1/3600h) · 简写 sec",
};

// ===== 动态预设函数（根据模式切换）=====
const standardHintsRad = [
    "sin(x)", "cos(x)", "tan(x)", "sqrt(x)", "cbrt(x)",
    "ln(x)", "lg(x)", "pow(x,y)", "abs(x)", "sign(x)",
    "floor(x)", "ceil(x)", "round(x)", "mod(x,y)",
    "sinh(x)", "cosh(x)", "tanh(x)", "hypot(x,y)",
    "deg(x)", "rad(x)", "nCr(n,r)", "nPr(n,r)", "x!",
    "x%", "hex2dec(x)", "bin2dec(x)", "pi", "e",
    "1/x", "x^2", "x^3", "km", "Hour", "Min", "Second",
];
const standardHintsDeg = [
    "sind(x)", "cosd(x)", "tand(x)", "sqrt(x)", "cbrt(x)",
    "ln(x)", "lg(x)", "pow(x,y)", "abs(x)", "sign(x)",
    "floor(x)", "ceil(x)", "round(x)", "mod(x,y)",
    "sinh(x)", "cosh(x)", "tanh(x)", "hypot(x,y)",
    "deg(x)", "rad(x)", "nCr(n,r)", "nPr(n,r)", "x!",
    "x%", "hex2dec(x)", "bin2dec(x)", "pi", "e",
    "1/x", "x^2", "x^3", "km", "Hour", "Min", "Second",
];
const standardHintsRadInv = [
    "asin(x)", "acos(x)", "atan(x)", "sqrt(x)", "cbrt(x)",
    "ln(x)", "lg(x)", "pow(x,y)", "abs(x)", "sign(x)",
    "floor(x)", "ceil(x)", "round(x)", "mod(x,y)",
    "sinh(x)", "cosh(x)", "tanh(x)", "hypot(x,y)",
    "deg(x)", "rad(x)", "nCr(n,r)", "nPr(n,r)", "x!",
    "x%", "hex2dec(x)", "bin2dec(x)", "pi", "e",
    "1/x", "x^2", "x^3", "km", "Hour", "Min", "Second",
];
const standardHintsDegInv = [
    "asin(x)", "acos(x)", "atan(x)", "sqrt(x)", "cbrt(x)",
    "ln(x)", "lg(x)", "pow(x,y)", "abs(x)", "sign(x)",
    "floor(x)", "ceil(x)", "round(x)", "mod(x,y)",
    "sinh(x)", "cosh(x)", "tanh(x)", "hypot(x,y)",
    "deg(x)", "rad(x)", "nCr(n,r)", "nPr(n,r)", "x!",
    "x%", "hex2dec(x)", "bin2dec(x)", "pi", "e",
    "km", "Hour", "Min", "Second",
];

const solveHints = [
    "ax^2+bx+c=0", "ax+b=0", "x^2+px+q=0", "ax^2+bx=0",
    "ax^3+bx^2+cx+d=0", "a/x+b=c", "sqrt(ax+b)=c",
    "a^x=b", "ln(x)=a", "abs(x)=a",
    "sin(x)=a", "cos(x)=a", "tan(x)=a",
];

const HINT_ROW_COUNT = 6; // 固定行数，保持 UI 高度一致

const displayHints = computed(() => {
    const cols = calcMode.value === 'solve' ? 4 : 5;
    const total = HINT_ROW_COUNT * cols;
    let hints;
    if (calcMode.value === 'solve') hints = solveHints;
    else if (useDegrees.value) {
        hints = useInverse.value ? standardHintsDegInv : standardHintsDeg;
    } else {
        hints = useInverse.value ? standardHintsRadInv : standardHintsRad;
    }
    // 补齐到固定数量，保持预设功能区高度不变
    const padded = [...hints];
    while (padded.length < total) padded.push(null);
    return padded;
});

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

// ===== 方程求解（增强版：支持一次/二次/三次，含解题步骤）=====
const solveSteps = ref([]);     // 解题步骤数组
const solveResult = ref(null);  // 详细求解结果

// 解析多项式表达式，提取各项系数 [c0, c1, c2, c3] 对应常数项、x、x²、x³
function parsePolynomial(expr) {
    let s = expr.replace(/\s/g, '').toLowerCase();
    // 统一幂符号
    s = s.replace(/\^/g, '^');
    // 处理隐式乘法: 2x → 2*x, x2 → x*2, 3x^2 → 3*x^2, (x+1)(x+2) → (x+1)*(x+2)
    s = s.replace(/(\d)(x)/g, '$1*x');
    s = s.replace(/(x)(\d)/g, '$1*$2');
    s = s.replace(/\)\(/g, ')*(');
    s = s.replace(/(\d)\(/g, '$1*(');
    s = s.replace(/\)(\d)/g, ')*$1');

    // 提取系数：用 x^3, x^2, x, 常数项采样
    const coeffs = [0, 0, 0, 0]; // [c, b, a, a3] for ax^3+bx^2+cx+d

    // 用数值采样法提取各次幂系数（精确解析多项式）
    function evalAt(val) {
        const substituted = s.replace(/x/g, `(${val})`).replace(/\^/g, '**');
        try {
            return new Function(`"use strict"; return (${substituted});`)();
        } catch { return NaN; }
    }

    // 采样 4 个点解出 4 个系数 (假设最高次 ≤ 3)
    const f0 = evalAt(0);          // f(0) = d
    const f1 = evalAt(1);          // f(1) = a+b+c+d
    const fm1 = evalAt(-1);        // f(-1) = -a+b-c+d (for cubic: -a3+a2-a1+a0)
    const f2 = evalAt(2);          // f(2) = 8a3+4a2+2a1+a0

    if ([f0, f1, fm1, f2].some(v => isNaN(v) || !isFinite(v))) {
        throw new Error("表达式无法解析，请检查格式");
    }

    // 解线性方程组求系数
    // f0 = d
    // f1 = a3 + a2 + a1 + d
    // fm1 = -a3 + a2 - a1 + d
    // f2 = 8a3 + 4a2 + 2a1 + d
    const d = f0;
    const sum1 = f1 - d;       // a3 + a2 + a1
    const sumM1 = fm1 - d;     // -a3 + a2 - a1
    const sum2 = f2 - d;       // 8a3 + 4a2 + 2a1

    const a2_plus_a0 = (sum1 + sumM1) / 2;  // a2
    const a3_plus_a1 = (sum1 - sumM1) / 2;  // a3 + a1

    // 8a3 + 4a2 + 2a1 = sum2
    // a3 + a1 = a3_plus_a1 → a1 = a3_plus_a1 - a3
    // 8a3 + 4*a2_plus_a0 + 2*(a3_plus_a1 - a3) = sum2
    // 8a3 + 4*a2_plus_a0 + 2*a3_plus_a1 - 2a3 = sum2
    // 6a3 = sum2 - 4*a2_plus_a0 - 2*a3_plus_a1
    const a3 = (sum2 - 4 * a2_plus_a0 - 2 * a3_plus_a1) / 6;
    const a1 = a3_plus_a1 - a3;

    return {
        a3, a2: a2_plus_a0, a1, a0: d,
        // 返回 [常数项, x系数, x²系数, x³系数]
        coeffs: [d, a1, a2_plus_a0, a3],
    };
}

function solveEquation(equationStr) {
    solveSteps.value = [];
    solveResult.value = null;
    const steps = [];

    function done(result) {
        solveSteps.value = steps;
        solveResult.value = result;
        return result;
    }

    let eq = equationStr.replace(/\s/g, '').toLowerCase();
    const parts = eq.split('=');
    if (parts.length !== 2) throw new Error("请输入正确的方程格式（含=）");

    const left = parts[0] || '0';
    const right = parts[1] || '0';

    steps.push({ text: `原方程: ${left} = ${right}`, hl: false });

    // ===== 非多项式方程检测 =====
    // 直接分析原始左右两边（不做移项），匹配特定模式

    // sqrt(ax+b) = c  或  sqrt(ax+b) = c
    let m = left.match(/^sqrt\((.+)\)$/) || left.match(/^√\((.+)\)$/);
    if (m) {
        const inner = m[1];
        const result = solveRadical(inner, right, steps);
        if (result) {
            return done(result);
        }
    }

    // a/x + b = c  (左式含 /x)
    m = left.match(/^(.+)\/x\s*([+-].+)?$/);
    if (m && !left.includes('^') && !left.includes('sqrt') && !left.includes('sin') && !left.includes('cos') && !left.includes('tan') && !left.includes('ln') && !left.includes('abs')) {
        const result = solveRational(left, right, steps);
        if (result) {
            return done(result);
        }
    }

    // a^x = b  (指数方程)
    if (/^[\d.]+?\^x$/.test(left) && /^[\d.+-]+$/.test(right)) {
        const result = solveExponential(left, right, steps);
        if (result) {
            return done(result);
        }
    }

    // ln(x) = a  (对数方程)
    if (/^ln\(x\)$/.test(left) && /^[\d.+-]+$/.test(right)) {
        const result = solveLogarithmic(right, steps);
        if (result) {
            return done(result);
        }
    }

    // |x| = a 或 abs(x) = a (绝对值方程)
    m = left.match(/^abs\((.+)\)$/) || left.match(/^\|(.+)\|$/);
    if (m && /^[\d.+-]+$/.test(right)) {
        const result = solveAbsolute(m[1], right, steps);
        if (result) {
            return done(result);
        }
    }

    // sin(x)=a, cos(x)=a, tan(x)=a (三角方程)
    m = left.match(/^(sin|cos|tan)\((.+)\)$/);
    if (m && /^[\d.+-]+$/.test(right)) {
        const result = solveTrig(m[1], m[2], right, steps);
        if (result) {
            return done(result);
        }
    }

    // ===== 多项式方程求解 =====
    // 移项：左 - 右 = 0
    const combinedExpr = `(${left})-(${right})`;
    steps.push({ text: `移项: ${combinedExpr} = 0`, hl: false });

    const poly = parsePolynomial(combinedExpr);
    const [c, b, a, a3] = poly.coeffs;

    // 确定有效次数（从高到低）
    const eps = 1e-10;
    let degree = 0;
    if (Math.abs(a3) > eps) degree = 3;
    else if (Math.abs(a) > eps) degree = 2;
    else if (Math.abs(b) > eps) degree = 1;

    // 显示化简后的方程
    const simplified = fmtPoly([a3, a, b, c], ['x^3', 'x^2', 'x', '']);
    steps.push({ text: `化简: ${simplified} = 0`, hl: true });

    let result;

    if (degree === 3) {
        result = solveCubic(a3, a, b, c, steps);
    } else if (degree === 2) {
        result = solveQuadratic(a, b, c, steps);
    } else if (degree === 1) {
        result = solveLinear(b, c, steps);
    } else {
        if (Math.abs(c) < eps) {
            result = { type: 'identity', solutions: [], display: '恒等式，任意 x 均成立' };
            steps.push({ text: '0 = 0，恒等式，任意 x 均成立', hl: false });
        } else {
            result = { type: 'contradiction', solutions: [], display: '矛盾方程，无解' };
            steps.push({ text: `${formatNum(c)} = 0，矛盾，无解`, hl: false });
        }
    }

    return done(result);
}

// ===== 非多项式方程求解器 =====

function solveRadical(inner, right, steps) {
    // sqrt(ax+b) = c  →  ax+b = c²  →  x = (c²-b)/a
    // inner 格式: ax+b 或 x+b 或 ax
    steps.push({ text: `根式方程: √(${inner}) = ${right}`, hl: true });
    const c = safeEvalSimple(right);
    if (isNaN(c) || c < 0) throw new Error("根式方程右边必须 ≥ 0");
    const c2 = c * c;
    steps.push({ text: `两边平方: ${inner} = ${right}² = ${formatNum(c2)}`, hl: false });

    const poly = parsePolynomial(`(${inner})-(${formatNum(c2)})`);
    const [d, b, a] = poly.coeffs;

    if (Math.abs(a) > 1e-10) {
        steps.push({ text: `化为: ${formatCoeff2(a)}x ${formatCoeff2(b)} = 0`, hl: false });
        const x = -b / a;
        steps.push({ text: `x = ${formatNum(-b)} / ${formatNum(a)} = ${formatNum(x)}`, hl: false });
        steps.push({ text: `✓ x = ${formatNum(x)}`, hl: true });
        return { type: 'radical', degree: 1, solutions: [formatNum(x)], display: `x = ${formatNum(x)}` };
    } else if (Math.abs(b) > 1e-10) {
        const x = -d / b;
        steps.push({ text: `x = ${formatNum(-d)} / ${formatNum(b)} = ${formatNum(x)}`, hl: false });
        steps.push({ text: `✓ x = ${formatNum(x)}`, hl: true });
        return { type: 'radical', degree: 1, solutions: [formatNum(x)], display: `x = ${formatNum(x)}` };
    }
    throw new Error("根式方程无法求解");
}

function solveRational(left, right, steps) {
    // a/x + b = c  →  a/x = c-b  →  x = a/(c-b)
    steps.push({ text: `分式方程: ${left} = ${right}`, hl: true });
    const c = safeEvalSimple(right.replace(/\^/g, '**'));
    if (isNaN(c)) throw new Error("右边无法计算");

    // 解析 a/x + b 形式
    const parts = left.split(/([+-])/);
    let a = 1, b = 0, sign = 1;
    for (let i = 0; i < parts.length; i++) {
        const p = parts[i].trim();
        if (p === '+') sign = 1;
        else if (p === '-') sign = -1;
        else if (p.includes('/x')) {
            const num = p.replace('/x', '').trim();
            a = sign * (num === '' || num === '+' ? 1 : num === '-' ? -1 : safeEvalSimple(num));
        } else if (p && !p.includes('/')) {
            b += sign * safeEvalSimple(p);
        }
    }
    if (isNaN(a) || isNaN(b)) throw new Error("分式方程格式无法解析");

    steps.push({ text: `a = ${formatNum(a)}, b = ${formatNum(b)}, c = ${formatNum(c)}`, hl: false });
    const denom = c - b;
    if (Math.abs(denom) < 1e-10) throw new Error("分母为零，无解");
    const x = a / denom;
    steps.push({ text: `${formatNum(a)}/x = ${formatNum(c)} − ${formatNum(b)} = ${formatNum(denom)}`, hl: false });
    steps.push({ text: `x = ${formatNum(a)} / ${formatNum(denom)} = ${formatNum(x)}`, hl: false });
    steps.push({ text: `✓ x = ${formatNum(x)}`, hl: true });
    return { type: 'rational', degree: 1, solutions: [formatNum(x)], display: `x = ${formatNum(x)}` };
}

function solveExponential(left, right, steps) {
    // a^x = b  →  x = ln(b)/ln(a)
    const a = parseFloat(left.replace('^x', ''));
    const b = parseFloat(right);
    if (a <= 0 || a === 1) throw new Error("指数底数必须 > 0 且 ≠ 1");
    if (b <= 0) throw new Error("指数方程右边必须 > 0");
    steps.push({ text: `指数方程: ${a}^x = ${b}`, hl: true });
    steps.push({ text: `取自然对数: x·ln(${a}) = ln(${b})`, hl: false });
    const x = Math.log(b) / Math.log(a);
    steps.push({ text: `x = ln(${b}) / ln(${a}) = ${formatNum(x)}`, hl: false });
    steps.push({ text: `✓ x = ${formatNum(x)}`, hl: true });
    return { type: 'exponential', degree: 0, solutions: [formatNum(x)], display: `x = ${formatNum(x)}` };
}

function solveLogarithmic(right, steps) {
    // ln(x) = a  →  x = e^a
    const a = safeEvalSimple(right);
    steps.push({ text: `对数方程: ln(x) = ${formatNum(a)}`, hl: true });
    const x = Math.exp(a);
    steps.push({ text: `x = e^${formatNum(a)} = ${formatNum(x)}`, hl: false });
    steps.push({ text: `✓ x = ${formatNum(x)}`, hl: true });
    return { type: 'logarithmic', degree: 0, solutions: [formatNum(x)], display: `x = ${formatNum(x)}` };
}

function solveAbsolute(inner, right, steps) {
    // |x| = a  →  x = ±a
    const a = safeEvalSimple(right);
    if (a < 0) {
        steps.push({ text: `|${inner}| = ${formatNum(a)} < 0，无解`, hl: true });
        return { type: 'absolute', degree: 0, solutions: [], display: '无解' };
    }
    steps.push({ text: `绝对值方程: |${inner}| = ${formatNum(a)}`, hl: true });
    if (Math.abs(a) < 1e-10) {
        steps.push({ text: `✓ x = 0`, hl: true });
        return { type: 'absolute', degree: 0, solutions: ['0'], display: 'x = 0' };
    }
    steps.push({ text: `✓ x₁ = ${formatNum(a)}`, hl: true });
    steps.push({ text: `✓ x₂ = ${formatNum(-a)}`, hl: true });
    return { type: 'absolute', degree: 0, solutions: [formatNum(a), formatNum(-a)], display: `x₁ = ${formatNum(a)}  |  x₂ = ${formatNum(-a)}` };
}

function solveTrig(func, inner, right, steps) {
    const a = safeEvalSimple(right);
    steps.push({ text: `三角方程: ${func}(${inner}) = ${formatNum(a)}`, hl: true });
    if (Math.abs(a) > 1) throw new Error(`${func} 的值域为 [-1, 1]，${formatNum(a)} 超出范围`);

    const useDeg = useDegrees.value;
    const radVal = func === 'sin' ? Math.asin(a) : func === 'cos' ? Math.acos(a) : Math.atan(a);
    const degVal = radVal * 180 / Math.PI;

    if (func === 'sin') {
        if (useDeg) {
            steps.push({ text: `x₁ = arcsin(${formatNum(a)}) = ${formatNum(degVal)}°`, hl: false });
            steps.push({ text: `✓ x₁ = ${formatNum(degVal)}°`, hl: true });
            const x2 = 180 - degVal;
            steps.push({ text: `x₂ = 180° − ${formatNum(degVal)}° = ${formatNum(x2)}°`, hl: false });
            steps.push({ text: `✓ x₂ = ${formatNum(x2)}°`, hl: true });
            return { type: 'trig', degree: 0, solutions: [formatNum(degVal) + '°', formatNum(x2) + '°'], display: `x₁ = ${formatNum(degVal)}°  |  x₂ = ${formatNum(x2)}°` };
        }
        steps.push({ text: `x₁ = arcsin(${formatNum(a)}) = ${formatNum(radVal)} rad`, hl: false });
        const x2 = Math.PI - radVal;
        steps.push({ text: `x₂ = π − ${formatNum(radVal)} = ${formatNum(x2)} rad`, hl: false });
        steps.push({ text: `✓ x₁ = ${formatNum(radVal)} rad  |  x₂ = ${formatNum(x2)} rad`, hl: true });
        return { type: 'trig', degree: 0, solutions: [formatNum(radVal) + ' rad', formatNum(x2) + ' rad'], display: `x₁ = ${formatNum(radVal)} rad  |  x₂ = ${formatNum(x2)} rad` };
    } else if (func === 'cos') {
        if (useDeg) {
            steps.push({ text: `x₁ = arccos(${formatNum(a)}) = ${formatNum(degVal)}°`, hl: false });
            steps.push({ text: `✓ x₁ = ${formatNum(degVal)}°`, hl: true });
            const x2 = -degVal;
            steps.push({ text: `x₂ = −${formatNum(degVal)}°`, hl: false });
            steps.push({ text: `✓ x₂ = ${formatNum(x2)}°`, hl: true });
            return { type: 'trig', degree: 0, solutions: [formatNum(degVal) + '°', formatNum(x2) + '°'], display: `x₁ = ${formatNum(degVal)}°  |  x₂ = ${formatNum(x2)}°` };
        }
        steps.push({ text: `x₁ = arccos(${formatNum(a)}) = ${formatNum(radVal)} rad`, hl: false });
        const x2 = -radVal;
        steps.push({ text: `✓ x₁ = ${formatNum(radVal)} rad  |  x₂ = ${formatNum(x2)} rad`, hl: true });
        return { type: 'trig', degree: 0, solutions: [formatNum(radVal) + ' rad', formatNum(x2) + ' rad'], display: `x₁ = ${formatNum(radVal)} rad  |  x₂ = ${formatNum(x2)} rad` };
    } else { // tan
        if (useDeg) {
            steps.push({ text: `x = arctan(${formatNum(a)}) = ${formatNum(degVal)}°`, hl: false });
            steps.push({ text: `✓ x = ${formatNum(degVal)}° + k·180° (k∈Z)`, hl: true });
            return { type: 'trig', degree: 0, solutions: [formatNum(degVal) + '°'], display: `x = ${formatNum(degVal)}°` };
        }
        steps.push({ text: `x = arctan(${formatNum(a)}) = ${formatNum(radVal)} rad`, hl: false });
        steps.push({ text: `✓ x = ${formatNum(radVal)} rad + kπ (k∈Z)`, hl: true });
        return { type: 'trig', degree: 0, solutions: [formatNum(radVal) + ' rad'], display: `x = ${formatNum(radVal)} rad` };
    }
}

// 简单表达式求值（不使用数学函数库）
function safeEvalSimple(expr) {
    const s = String(expr).trim().replace(/\^/g, '**');
    try {
        return new Function(`"use strict"; return (${s});`)();
    } catch {
        return NaN;
    }
}

function formatCoeff(v) {
    if (Math.abs(v - 1) < 1e-10) return '1';
    if (Math.abs(v + 1) < 1e-10) return '-1';
    return formatNum(v);
}

function solveLinear(b, c, steps) {
    const eqText = fmtPoly([b, c], ['x', '']);
    steps.push({ text: `一次方程: ${eqText} = 0`, hl: true });
    const x = -c / b;
    steps.push({ text: `移项: ${formatCoeff2(b)}x = ${formatNum(-c)}`, hl: false });
    steps.push({ text: `x = ${formatNum(-c)} ÷ ${formatNum(b)} = ${formatNum(x)}`, hl: false });
    steps.push({ text: `✓ 解: x = ${formatNum(x)}`, hl: true });
    return {
        type: 'linear', b, c, degree: 1,
        solutions: [formatNum(x)], display: `x = ${formatNum(x)}`,
    };
}

// 格式化多项式: [a, b, c, d] → "ax^3 + bx^2 + cx + d"
function fmtPoly(coeffs, vars = ['x^3', 'x^2', 'x', '']) {
    const terms = [];
    for (let i = 0; i < coeffs.length; i++) {
        const v = coeffs[i];
        if (Math.abs(v) < 1e-10) continue;
        const sign = terms.length === 0 ? (v < 0 ? '-' : '') : (v >= 0 ? ' + ' : ' - ');
        const absVal = Math.abs(v);
        const varPart = vars[i] || '';
        if (Math.abs(absVal - 1) < 1e-10 && varPart) {
            terms.push(`${sign}${varPart}`);
        } else {
            terms.push(`${sign}${formatNum(absVal)}${varPart}`);
        }
    }
    return terms.join('') || '0';
}

function solveQuadratic(a, b, c, steps) {
    const eqText = fmtPoly([a, b, c], ['x^2', 'x', '']);
    steps.push({ text: `二次方程: ${eqText} = 0`, hl: true });
    steps.push({ text: `系数: a = ${formatNum(a)}, b = ${formatNum(b)}, c = ${formatNum(c)}`, hl: false });

    const delta = b * b - 4 * a * c;
    steps.push({ text: `判别式 Δ = b² − 4ac = ${formatNum(b)}² − 4×${formatNum(a)}×${formatNum(c)} = ${formatNum(delta)}`, hl: false });

    if (delta < -1e-10) {
        const realPart = -b / (2 * a);
        const imagPart = Math.sqrt(-delta) / (2 * a);
        steps.push({ text: `Δ < 0，有两个共轭复根`, hl: false });
        steps.push({ text: `求根公式: x = (−b ± √Δ) / (2a) = (${formatNum(-b)} ± √${formatNum(-delta)}i) / ${formatNum(2 * a)}`, hl: false });
        steps.push({ text: `实部 = −b/(2a) = ${formatNum(realPart)}`, hl: false });
        steps.push({ text: `虚部 = √(−Δ)/(2a) = ${formatNum(imagPart)}`, hl: false });
        const display = `x₁ = ${formatNum(realPart)} + ${formatNum(imagPart)}i\nx₂ = ${formatNum(realPart)} − ${formatNum(imagPart)}i`;
        steps.push({ text: `✓ x₁ = ${formatNum(realPart)} + ${formatNum(imagPart)}i`, hl: true });
        steps.push({ text: `✓ x₂ = ${formatNum(realPart)} − ${formatNum(imagPart)}i`, hl: true });
        return {
            type: 'quadratic', a, b, c, delta, degree: 2,
            solutions: [`${formatNum(realPart)}+${formatNum(imagPart)}i`, `${formatNum(realPart)}-${formatNum(imagPart)}i`],
            display,
        };
    } else if (Math.abs(delta) < 1e-10) {
        const x = -b / (2 * a);
        steps.push({ text: `Δ = 0，有一个重根`, hl: false });
        steps.push({ text: `x = −b/(2a) = ${formatNum(-b)} / ${formatNum(2 * a)} = ${formatNum(x)}`, hl: false });
        const display = `x = ${formatNum(x)} (重根)`;
        steps.push({ text: `✓ ${display}`, hl: true });
        return {
            type: 'quadratic', a, b, c, delta: 0, degree: 2,
            solutions: [formatNum(x)], display,
        };
    } else {
        const sqrtDelta = Math.sqrt(delta);
        const x1 = (-b + sqrtDelta) / (2 * a);
        const x2 = (-b - sqrtDelta) / (2 * a);
        steps.push({ text: `Δ > 0，有两个不等实根`, hl: false });
        steps.push({ text: `√Δ = √${formatNum(delta)} = ${formatNum(sqrtDelta)}`, hl: false });
        steps.push({ text: `x₁ = (−b + √Δ)/(2a) = (${formatNum(-b)} + ${formatNum(sqrtDelta)}) / ${formatNum(2 * a)} = ${formatNum(x1)}`, hl: false });
        steps.push({ text: `x₂ = (−b − √Δ)/(2a) = (${formatNum(-b)} − ${formatNum(sqrtDelta)}) / ${formatNum(2 * a)} = ${formatNum(x2)}`, hl: false });
        const display = `x₁ = ${formatNum(x1)}\nx₂ = ${formatNum(x2)}`;
        steps.push({ text: `✓ x₁ = ${formatNum(x1)}`, hl: true });
        steps.push({ text: `✓ x₂ = ${formatNum(x2)}`, hl: true });
        return {
            type: 'quadratic', a, b, c, delta, degree: 2,
            solutions: [formatNum(x1), formatNum(x2)], display,
        };
    }
}

function solveCubic(a3, a2, a1, a0, steps) {
    const eqText = fmtPoly([a3, a2, a1, a0], ['x^3', 'x^2', 'x', '']);
    steps.push({ text: `三次方程: ${eqText} = 0`, hl: true });

    // 化为标准形式 x³ + px² + qx + r = 0
    const p = a2 / a3;
    const q = a1 / a3;
    const r = a0 / a3;
    const stdEq = fmtPoly([1, p, q, r], ['x^3', 'x^2', 'x', '']);
    steps.push({ text: `标准化 (除以${formatNum(a3)}): ${stdEq} = 0`, hl: false });

    // 用 Cardano 方法
    // 先消去二次项: 令 x = y - p/3, 得 y³ + Py + Q = 0
    const P = q - (p * p) / 3;
    const Q = r - (p * q) / 3 + (2 * p * p * p) / 27;
    steps.push({ text: `令 x = y - p/3, 消去二次项:`, hl: false });
    steps.push({ text: `P = q - p²/3 = ${formatNum(P)}`, hl: false });
    steps.push({ text: `Q = r - pq/3 + 2p³/27 = ${formatNum(Q)}`, hl: false });
    const depEq = fmtPoly([1, 0, P, Q], ['y^3', 'y^2', 'y', '']);
    steps.push({ text: `化为: ${depEq} = 0`, hl: true });

    const discriminant = (Q * Q) / 4 + (P * P * P) / 27;
    steps.push({ text: `判别式: Δ = Q²/4 + P³/27 = ${formatNum(discriminant)}`, hl: false });

    const solutions = [];
    const shift = p / 3; // 回代偏移量

    if (Math.abs(discriminant) < 1e-10) {
        // Δ = 0：三个实根（至少两个相等）
        steps.push({ text: 'Δ = 0，有三个实根（至少两个相等）', hl: false });
        const u = Math.cbrt(-Q / 2);
        const x1 = 2 * u - shift;
        const x2 = -u - shift;
        solutions.push(formatNum(x1), formatNum(x2), formatNum(x2));
        steps.push({ text: `u = ∛(−Q/2) = ${formatNum(u)}`, hl: false });
        steps.push({ text: `✓ x₁ = 2u − p/3 = ${formatNum(x1)}`, hl: true });
        steps.push({ text: `✓ x₂ = x₃ = −u − p/3 = ${formatNum(x2)} (重根)`, hl: true });
    } else if (discriminant > 1e-10) {
        // Δ > 0：一个实根 + 两个共轭复根
        steps.push({ text: 'Δ > 0，有一个实根和两个共轭复根', hl: false });
        const sqrtD = Math.sqrt(discriminant);
        const u = Math.cbrt(-Q / 2 + sqrtD);
        const v = Math.cbrt(-Q / 2 - sqrtD);
        const x1 = u + v - shift;
        solutions.push(formatNum(x1));
        steps.push({ text: `√Δ = ${formatNum(sqrtD)}`, hl: false });
        steps.push({ text: `u = ∛(−Q/2 + √Δ) = ${formatNum(u)}`, hl: false });
        steps.push({ text: `v = ∛(−Q/2 − √Δ) = ${formatNum(v)}`, hl: false });

        const realPart = -(u + v) / 2 - shift;
        const imagPart = (Math.sqrt(3) / 2) * (u - v);
        solutions.push(`${formatNum(realPart)}+${formatNum(Math.abs(imagPart))}i`);
        solutions.push(`${formatNum(realPart)}-${formatNum(Math.abs(imagPart))}i`);
        steps.push({ text: `✓ x₁ = u + v − p/3 = ${formatNum(x1)} (实根)`, hl: true });
        steps.push({ text: `✓ x₂ = ${formatNum(realPart)} + ${formatNum(Math.abs(imagPart))}i`, hl: true });
        steps.push({ text: `✓ x₃ = ${formatNum(realPart)} − ${formatNum(Math.abs(imagPart))}i`, hl: true });
    } else {
        // Δ < 0：三个不等实根（三角函数法）
        steps.push({ text: 'Δ < 0，有三个不等实根（三角函数法）', hl: false });
        const phi = Math.acos((-Q / 2) / Math.sqrt(-(P * P * P) / 27));
        const r = 2 * Math.sqrt(-P / 3);
        steps.push({ text: `φ = arccos(−Q/2 / √(−P³/27)) = ${formatNum(phi)} rad`, hl: false });
        steps.push({ text: `r = 2√(−P/3) = ${formatNum(r)}`, hl: false });
        for (let k = 0; k < 3; k++) {
            const angle = (phi + 2 * Math.PI * k) / 3;
            const xk = r * Math.cos(angle) - shift;
            solutions.push(formatNum(xk));
            steps.push({ text: `✓ x${k + 1} = r·cos((φ+2π·${k})/3) − p/3 = ${formatNum(xk)}`, hl: true });
        }
    }

    const display = solutions.map((s, i) => `x${subNum(i + 1)} = ${s}`).join('\n');
    return {
        type: 'cubic', degree: 3,
        a3, a: a2, b: a1, c: a0,
        solutions, display,
    };
}

function formatCoeff2(v) {
    if (Math.abs(v - 1) < 1e-10) return '+';
    if (Math.abs(v + 1) < 1e-10) return '-';
    if (v >= 0) return `+${formatNum(v)}`;
    return `-${formatNum(Math.abs(v))}`;
}

function subNum(n) {
    const subs = ['₀', '₁', '₂', '₃', '₄', '₅'];
    return subs[n] || String(n);
}

// 插入方程模板到输入栏
function insertSolveHint(hint) {
    playClick();
    inputText.value = hint;
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
    // 方程模板：直接替换输入
    if (calcMode.value === 'solve' && hint.includes('=')) {
        inputText.value = hint;
        return;
    }
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
        } else if (isNumber && hint === "1/x") {
            inputText.value = `1/(${trimmed})`;
        } else if (isNumber && hint === "x^2") {
            inputText.value = `${trimmed}^2`;
        } else if (isNumber && hint === "x^3") {
            inputText.value = `${trimmed}^3`;
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

    // ===== 方程求解模式 =====
    if (calcMode.value === 'solve' && input.includes('=')) {
        try {
            const result = solveEquation(input);
            numbers.value = result.solutions.map(s => {
                const match = String(s).match(/^([-+]?\d+\.?\d*)/);
                return match ? Number(match[1]) : NaN;
            }).filter(n => !isNaN(n));
            displayResult.value = result.display.replace(/\n/g, '  |  ');
            lastInput.value = input;
            lastResultValue.value = numbers.value.length > 0 ? numbers.value[0] : null;
            addHistory("SOLVE", input, numbers.value.filter(n => isFinite(n)));
            inputText.value = "";
            return;
        } catch (err) {
            errorMsg.value = err.message || String(err);
            return;
        }
    }

    // ===== 标准计算模式 =====
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
                        <span class="status-mode">{{ calcMode === 'solve' ? 'SOLVE' : 'COMP' }}</span>
                        <span v-if="useDegrees" class="status-deg">DEG</span>
                        <span v-else class="status-deg">RAD</span>
                        <span v-if="useInverse" class="status-inv">INV</span>
                        <span v-if="stats" class="status-stat">STAT</span>
                        <span class="status-mem" v-if="history.length">M</span>
                        <span class="status-bat">▮▮▮</span>
                    </div>
                    <div class="screen-expr" :class="{ 'screen-hidden': !(displayResult && lastInput) && calcMode !== 'solve' }">
                        {{ lastInput || '\u00A0' }}
                    </div>
                    <div class="screen-input">
                        <input v-model="inputText" class="screen-input-field"
                            :placeholder="displayResult ? '' : (calcMode === 'solve' ? '输入方程...' : '输入表达式，逗号/空格分隔多值...')"
                            @keydown.space.prevent="inputText += ' '" @keyup.enter="handleKeyboardSubmit" />
                    </div>
                    <div class="screen-output">
                        <div class="output-row" ref="outputRow"
                            @mousedown="startDragScroll" @mousemove="dragScroll" @mouseup="stopDragScroll" @mouseleave="stopDragScroll"
                            @touchstart="startDragScroll" @touchmove="dragScroll" @touchend="stopDragScroll">
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

                <!-- ===== 功能切换按钮行 ===== -->
                <div class="mode-toggle-row">
                    <button class="mode-btn mode-standard" :class="{ active: calcMode === 'standard' }"
                        @click="calcMode = 'standard'; playClick()" title="标准计算功能">
                        <span class="mode-icon">📐</span>标准
                    </button>
                    <button class="mode-btn mode-solve" :class="{ active: calcMode === 'solve' }"
                        @click="calcMode = 'solve'; playClick()" title="Solve equations">
                        <span class="mode-icon">🔢</span>方程
                    </button>
                    <button class="mode-btn mode-deg" :class="{ active: useDegrees }"
                        @click="useDegrees = !useDegrees; playClick()"
                        :title="useDegrees ? '当前：角度 (DEG)，点击切换弧度' : '当前：弧度 (RAD)，点击切换角度'">
                        <span class="mode-icon">{{ useDegrees ? '°' : 'π' }}</span>{{ useDegrees ? '角度' : '弧度' }}
                    </button>
                    <button class="mode-btn mode-inv" :class="{ active: useInverse }"
                        @click="useInverse = !useInverse; playClick()"
                        :title="useInverse ? '当前：反函数，点击切换正函数' : '当前：正函数，点击切换反函数'">
                        <span class="mode-icon">⁻¹</span>{{ useInverse ? '反函数' : '正函数' }}
                    </button>
                </div>

                <!-- ===== 预设函数矩阵（动态，固定高度）===== -->
                <div class="calc-hints-area" :class="{ 'hints-4col': calcMode === 'solve' }">
                    <template v-for="(h, i) in displayHints" :key="i">
                        <span v-if="h" class="hint-tag"
                            :class="{
                                'hint-pace': paceHints.has(h),
                                'hint-solve': calcMode === 'solve',
                            }"
                            @click="insertHint(h)"
                            @mouseenter="showTooltip($event, hintTooltips[h] || h)" @mouseleave="hideTooltip">{{ h }}</span>
                        <span v-else class="hint-tag hint-empty"></span>
                    </template>
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
                    <div class="calc-space-row" :class="{ 'has-eq': calcMode === 'solve' }">
                        <button class="calc-btn calc-space" :class="{ 'calc-pressed': activeKey === 'Space' }"
                            @click="calcKeyTap('Space')">SPACE</button>
                        <button v-if="calcMode === 'solve'" class="calc-btn calc-eq-key"
                            @click="playClick(); inputText += '='">=</button>
                    </div>
                    <div class="calc-bottom-row" :class="{ 'has-detail': stats }">
                        <button class="calc-btn calc-clear" :class="{ 'calc-pressed': activeKey === 'AC' }"
                            @click="calcClear">AC</button>
                        <button v-if="calcMode === 'standard'" class="calc-btn calc-equals" :class="{ 'calc-pressed': activeKey === '=' }"
                            @click="playClick(); handleKeyboardSubmit()">=</button>
                        <button v-if="calcMode === 'solve'" class="calc-btn calc-solve-btn"
                            @click="playClick(); handleKeyboardSubmit()">SOLVE</button>
                        <button v-if="stats" class="calc-btn calc-detail" @click="showStats = true">DETAIL</button>
                    </div>
                </div>
            </div>

            <!-- ====== 右侧：统计信息面板 ====== -->
            <div class="calc-info" :class="{ 'panel-hidden': !showStats }">
                <div class="info-top-bar">
                    <span class="info-brand">{{ calcMode === 'solve' && solveSteps.length > 0 ? 'SOLVE' : 'STAT' }}</span>
                    <button class="info-back-btn" @click="showStats = false">← 返回</button>
                </div>
                <div class="info-lcd">
                    <!-- ===== 解题过程（求解模式）===== -->
                    <div v-if="calcMode === 'solve' && solveSteps.length > 0" class="info-solve">
                        <div class="info-title">📐 解题过程</div>
                        <div class="solve-steps">
                            <div v-for="(step, i) in solveSteps" :key="i" class="solve-step"
                                :class="{ 'solve-step-hl': step.hl }">
                                <span class="solve-step-num">{{ i + 1 }}</span>
                                <span class="solve-step-text">{{ step.text }}</span>
                            </div>
                        </div>
                        <div class="solve-actions">
                            <button class="info-clear-btn info-clear-sm" @click="solveSteps = []; solveResult = null; showStats = false">清除</button>
                            <button class="info-back-btn" @click="showStats = false">← 返回</button>
                        </div>
                    </div>

                    <div v-if="!stats && history.length === 0 && !(calcMode === 'solve' && solveSteps.length > 0)" class="info-empty">
                        <span class="info-empty-icon">{{ calcMode === 'solve' ? '🔢' : '📊' }}</span>
                        <p>{{ calcMode === 'solve' ? 'Enter equation, press Enter to solve' : 'Enter data to see statistics' }}</p>
                    </div>

                    <div v-if="stats && !(calcMode === 'solve' && solveSteps.length > 0)" class="info-stats">
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

                    <div class="info-grade" v-if="stats && rankedData.length > 0 && !(calcMode === 'solve' && solveSteps.length > 0)">
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

                    <div v-if="history.length > 0 && !(calcMode === 'solve' && solveSteps.length > 0)" class="info-history">
                        <div class="info-title">历史记录</div>
                        <div class="history-list">
                            <div v-for="item in history" :key="item.id" class="history-item"
                                @click="fillFromHistory(item)">
                                <span class="history-input">{{ item.input }}</span>
                                <span class="history-result">{{ item.count }}个 · {{ formatNum(item.avg) }}</span>
                            </div>
                        </div>
                    </div>
                    <div v-if="!(calcMode === 'solve' && solveSteps.length > 0)" class="info-back-bottom">
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
    padding: env(safe-area-inset-top) 0 env(safe-area-inset-bottom) 0;
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
    overflow-x: auto;
    overflow-y: hidden;
    min-width: 0;
    cursor: grab;
    -webkit-overflow-scrolling: touch;
    scrollbar-width: thin;
    scrollbar-color: transparent transparent;
}

.output-row::-webkit-scrollbar {
    height: 3px;
}

.output-row::-webkit-scrollbar-thumb {
    background: #c0c4c8;
    border-radius: 3px;
}

.output-row::-webkit-scrollbar-track {
    background: transparent;
}

.output-value {
    font-size: 20px;
    font-weight: 800;
    color: #111;
    white-space: nowrap;
    flex-shrink: 0;
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

/* ---- 功能切换按钮行 ---- */
.mode-toggle-row {
    display: grid;
    grid-template-columns: repeat(4, 1fr);
    gap: 4px;
    margin-bottom: 5px;
    padding: 0 2px;
    flex-shrink: 0;
}

.mode-btn {
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 3px;
    padding: 7px 2px;
    font-size: 11px;
    font-weight: 700;
    border: none;
    border-radius: 5px;
    cursor: pointer;
    transition: all .15s;
    letter-spacing: 0.5px;
    font-family: "Helvetica Neue", "PingFang SC", "Microsoft YaHei", sans-serif;
    box-shadow: 0 3px 0 rgba(0, 0, 0, .18), 0 4px 6px rgba(0, 0, 0, .1);
    -webkit-tap-highlight-color: transparent;
    touch-action: manipulation;
    user-select: none;
    white-space: nowrap;
}

.mode-btn:active {
    transform: translateY(2px);
    box-shadow: 0 1px 0 rgba(0, 0, 0, .15), 0 2px 3px rgba(0, 0, 0, .08);
}

.mode-icon {
    font-size: 12px;
}

/* 标准 - 蓝色 */
.mode-standard {
    background: linear-gradient(180deg, #5b8def 0%, #4a7de0 40%, #3a6ad0 100%);
    color: #fff;
    box-shadow: 0 3px 0 #6b9df0, 0 4px 6px rgba(0, 0, 0, .12);
    border: 1px solid #3570c0;
}
.mode-standard:hover { filter: brightness(1.08); }
.mode-standard.active {
    background: linear-gradient(180deg, #7aadff 0%, #5b8def 40%, #4a7de0 100%);
    box-shadow: 0 1px 0 #6b9df0, 0 3px 8px rgba(74, 125, 224, .5), inset 0 1px 2px rgba(255,255,255,.2);
    transform: translateY(2px);
}

/* 求解 - 绿色 */
.mode-solve {
    background: linear-gradient(180deg, #4caf8e 0%, #3d9e7a 40%, #2e8b68 100%);
    color: #fff;
    box-shadow: 0 3px 0 #5dbf9f, 0 4px 6px rgba(0, 0, 0, .12);
    border: 1px solid #258060;
}
.mode-solve:hover { filter: brightness(1.08); }
.mode-solve.active {
    background: linear-gradient(180deg, #6dd4aa 0%, #4caf8e 40%, #3d9e7a 100%);
    box-shadow: 0 1px 0 #5dbf9f, 0 3px 8px rgba(61, 158, 122, .5), inset 0 1px 2px rgba(255,255,255,.2);
    transform: translateY(2px);
}

/* 弧度/角度 - 橙色 */
.mode-deg {
    background: linear-gradient(180deg, #f0a050 0%, #e09040 40%, #d08030 100%);
    color: #fff;
    box-shadow: 0 3px 0 #f5b565, 0 4px 6px rgba(0, 0, 0, .12);
    border: 1px solid #c07520;
}
.mode-deg:hover { filter: brightness(1.08); }
.mode-deg.active {
    background: linear-gradient(180deg, #f5b870 0%, #f0a050 40%, #e09040 100%);
    box-shadow: 0 1px 0 #f5b565, 0 3px 8px rgba(240, 160, 80, .5), inset 0 1px 2px rgba(255,255,255,.2);
    transform: translateY(2px);
}

/* 正/反函数 - 紫色 */
.mode-inv {
    background: linear-gradient(180deg, #8b6cc0 0%, #7a5bb0 40%, #6a4aa0 100%);
    color: #fff;
    box-shadow: 0 3px 0 #9c7dd0, 0 4px 6px rgba(0, 0, 0, .12);
    border: 1px solid #5a3890;
}
.mode-inv:hover { filter: brightness(1.08); }
.mode-inv.active {
    background: linear-gradient(180deg, #a080d8 0%, #8b6cc0 40%, #7a5bb0 100%);
    box-shadow: 0 1px 0 #9c7dd0, 0 3px 8px rgba(138, 108, 192, .5), inset 0 1px 2px rgba(255,255,255,.2);
    transform: translateY(2px);
}

/* 状态栏 DEG/RAD/INV 指示 */
.status-deg {
    color: #f0a050;
    font-weight: 700;
}
.status-inv {
    color: #8b6cc0;
    font-weight: 700;
}

/* 求解模式 hint 标签 - 绿色调 */
.hint-solve {
    background: linear-gradient(180deg, #3a6a4a 0%, #2e5a3a 40%, #224a2e 100%) !important;
    border-color: #4a8a5a !important;
    color: #a0e0b0 !important;
    font-size: 11px !important;
    letter-spacing: 0 !important;
    padding: 0 1px !important;
    box-shadow:
        0 3px 0 #4a7a5a,
        0 4px 8px rgba(0, 0, 0, .2),
        inset 0 1px 1px rgba(100, 220, 140, .15),
        inset 0 -1px 2px rgba(0, 0, 0, .15) !important;
}

.hint-solve:hover {
    filter: brightness(1.15) !important;
    border-color: #6aaa7a !important;
    color: #c0f0d0 !important;
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

/* 求解模式：4 列更宽 */
.calc-hints-area.hints-4col {
    grid-template-columns: repeat(4, 1fr);
}

.hint-tag {
    position: relative;
    display: flex;
    align-items: center;
    justify-content: center;
    height: 30px;
    padding: 0 2px;
    font-size: 11px;
    overflow: hidden;
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
    box-sizing: border-box;
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

/* 空占位：保持网格高度一致 */
.hint-empty {
    visibility: hidden;
    pointer-events: none;
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
    padding: 4px 10px;
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

/* ====== 解题步骤面板 ====== */
.info-solve {
    display: flex;
    flex-direction: column;
    height: 100%;
}

.solve-steps {
    flex: 1;
    overflow-y: auto;
    display: flex;
    flex-direction: column;
    gap: 2px;
    margin-bottom: 8px;
}

.solve-step {
    display: flex;
    align-items: flex-start;
    gap: 6px;
    padding: 5px 8px;
    border-radius: 4px;
    border: 1px solid transparent;
    font-size: 14px;
    font-family: "SF Mono", "Menlo", "Monaco", "Fira Code", "Courier New", monospace;
    font-feature-settings: "tnum";
    color: #555;
    background: transparent;
    transition: background .1s;
}

.solve-step:hover {
    background: #f0f2f4;
}

.solve-step-hl {
    background: #e8f0e8;
    border-color: #b0ccb0;
    color: #222;
    font-weight: 600;
}

.solve-step-hl:hover {
    background: #d8e8d8;
}

.solve-step-num {
    flex-shrink: 0;
    width: 18px;
    height: 18px;
    border-radius: 50%;
    background: #c0c4c8;
    color: #fff;
    font-size: 10px;
    font-weight: 700;
    display: flex;
    align-items: center;
    justify-content: center;
    font-family: "Helvetica Neue", "PingFang SC", sans-serif;
}

.solve-step-hl .solve-step-num {
    background: #4a8a5a;
}

.solve-step-text {
    line-height: 1.7;
    word-break: break-all;
    font-style: normal;
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

/* 解题面板小清除按钮 */
.info-clear-sm {
    width: auto;
    padding: 4px 10px;
    font-size: 10px;
    margin-top: 0;
    border: 1px solid #4a5054;
    border-radius: 4px;
}

.solve-actions {
    display: flex;
    gap: 6px;
    margin-top: 8px;
    justify-content: flex-end;
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
    margin-top: auto;
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

/* 求解模式：SPACE + = 双按钮 */
.calc-space-row.has-eq {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 8px;
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

/* 求解模式：= 输入键 */
.calc-btn.calc-eq-key {
    width: 100%;
    border-radius: 5px;
    background: linear-gradient(180deg, #5a6068 0%, #4a5054 40%, #3a3f42 100%);
    color: #fff;
    font-size: 1.1rem;
    font-weight: 700;
    padding: 14px 4px;
    box-shadow:
        0 4px 0 #6a7278,
        0 6px 10px rgba(0, 0, 0, .2),
        inset 0 1px 2px rgba(255, 255, 255, .12),
        inset 0 -1px 3px rgba(0, 0, 0, .1);
}

.calc-btn.calc-eq-key:active {
    transform: translateY(3px);
    box-shadow:
        0 1px 0 #6a7278,
        0 2px 4px rgba(0, 0, 0, .15);
}

/* 求解模式：绿色求解按钮 */
.calc-btn.calc-solve-btn {
    width: 100%;
    background: linear-gradient(180deg, #4caf8e 0%, #3d9e7a 45%, #2e8b68 100%);
    color: #fff;
    font-size: 1rem;
    font-weight: 700;
    border-radius: 6px;
    padding: 11px 4px;
    letter-spacing: 2px;
    box-shadow:
        0 4px 0 #5dbf9f,
        0 8px 16px rgba(0, 0, 0, .25),
        inset 0 2px 3px rgba(255, 255, 255, .25),
        inset 0 -2px 4px rgba(0, 0, 0, .1);
}

.calc-btn.calc-solve-btn:active {
    transform: translateY(3px);
    box-shadow:
        0 1px 0 #5dbf9f,
        0 3px 6px rgba(0, 0, 0, .2),
        inset 0 1px 2px rgba(255, 255, 255, .2);
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
