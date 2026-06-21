<script setup lang="ts">
import { ref, computed, onMounted, onUnmounted, nextTick, watch } from "vue";
import { solveEquation as solveEq } from "../utils/solver";
import { evaluateSingle, formatNum, splitTokens } from "../utils/evaluate";
import type { HistoryItem } from "../types";
import katex from "katex";

// KaTeX 混合渲染：将文本中的 $...$ 公式替换为 KaTeX HTML
function renderMath(text: string): string {
    return text.replace(/\$(.+?)\$/g, (_, formula: string) => {
        try {
            return katex.renderToString(formula, { throwOnError: false, displayMode: false });
        } catch {
            return formula;
        }
    });
}

// —— 内部类型 ——
interface TooltipState { show: boolean; text: string; x: number; y: number }
interface StatsResult { count: number; sum: number; max: number; min: number; avg: number; median: number; stddev: number; range: number }
interface RankedItem { idx: number; raw: number; rank: number; pct: number }
interface GradedItem extends RankedItem { grade: string }

const inputText = ref("0");
const numbers = ref<number[]>([]);
const errorMsg = ref("");
const history = ref<HistoryItem[]>([]);
const historyFilter = ref<'all' | 'calc' | 'solve' | 'stat'>('all');

const filteredHistory = computed(() => {
    if (historyFilter.value === 'all') return history.value;
    return history.value.filter(item => {
        if (historyFilter.value === 'solve') return item.source === 'SOLVE';
        if (historyFilter.value === 'stat') return item.source !== 'SOLVE' && (item.input.includes(' ') || /\d\s+\d/.test(item.input));
        if (historyFilter.value === 'calc') return item.source !== 'SOLVE' && !(item.input.includes(' ') || /\d\s+\d/.test(item.input));
        return true;
    });
});
const copiedIdx = ref(-1);
const quickPasteText = ref("");
const displayResult = ref<string | null>(null);
const lastInput = ref("");
const lastResultValue = ref<number | null>(null);
const aBound = ref(75);
const bBound = ref(50);
const cBound = ref(25);
const showGrade = ref(false);
const gradeSortKey = ref<"rank" | "idx" | "raw" | "pct" | "grade">("rank");
const gradeSortAsc = ref(true);
const showTouchPad = ref(true);
const showCalcPad = ref(true);
const showHints = ref(false);
const showStats = ref(false);
const showPace = ref(true);
const paceHints: Set<string> = new Set(['km', 'Hour', 'Min', 'Second']);
// C 按钮即将变 AC 的状态（内容保留，仅标签切换）
const cAcReady = ref(false);

// ===== 左右滑动切换面板 =====
const swipeStartX = ref(0);
const swipeStartY = ref(0);

function onTouchStart(e: TouchEvent): void {
    swipeStartX.value = e.touches[0].clientX;
    swipeStartY.value = e.touches[0].clientY;
}

function onTouchEnd(e: TouchEvent): void {
    const dx = e.changedTouches[0].clientX - swipeStartX.value;
    const dy = e.changedTouches[0].clientY - swipeStartY.value;
    // 仅水平滑动超过 50px 且大于垂直滑动时触发
    if (Math.abs(dx) > 50 && Math.abs(dx) > Math.abs(dy) * 1.5) {
        if (dx < 0) showStats.value = true;   // 左滑 → 详情
        else showStats.value = false;           // 右滑 → 计算器
    }
}

// ===== 历史记录滚动 =====
const historyIdx = ref(-1);   // -1 = 不在浏览中，0=最新，1=次新...
const savedInput = ref("");   // 进入历史浏览前的输入暂存

// ===== 功能模式 =====
const calcMode = ref<'standard' | 'solve' | 'tools'>('standard');
const useDegrees = ref(false);
const useInverse = ref(false);

// ===== 底部Tab导航 =====
const activeTab = ref<'basic' | 'equation' | 'stats' | 'tools'>('basic');

function switchTab(tab: 'basic' | 'equation' | 'stats' | 'tools'): void {
    playClick();
    activeTab.value = tab;
    if (tab === 'equation') {
        calcMode.value = 'solve';
    } else if (tab === 'tools') {
        calcMode.value = 'tools';
        showHints.value = true;
    } else if (tab === 'stats') {
        calcMode.value = 'standard';
        showStats.value = true;
    } else {
        calcMode.value = 'standard';
        showStats.value = false;
    }
}

// ===== LCD 动态字体大小 =====
const outputRow = ref<HTMLElement | null>(null);
const outputValueRef = ref<HTMLElement | null>(null);
const outputFontSize = ref(20);
const MIN_FONT_SIZE = 14;
const MAX_FONT_SIZE = 30;

function adjustFontSize(): void {
    const el = outputValueRef.value;
    if (!el) return;
    const parent = outputRow.value;
    if (!parent) return;
    requestAnimationFrame(() => {
        const maxWidth = parent.clientWidth;
        if (maxWidth <= 0) return;
        el.style.fontSize = MAX_FONT_SIZE + 'px';
        let size = MAX_FONT_SIZE;
        while (size > MIN_FONT_SIZE && el.scrollWidth > maxWidth) {
            size -= 1;
            el.style.fontSize = size + 'px';
        }
        outputFontSize.value = size;
    });
}

// ===== 全局 tooltip =====
const tooltip = ref<TooltipState>({ show: false, text: '', x: 0, y: 0 });
function showTooltip(e: MouseEvent, text: string): void {
    const target = e.target as HTMLElement;
    const rect = target.getBoundingClientRect();
    tooltip.value = { show: true, text, x: rect.left + rect.width / 2, y: rect.bottom + 8 };
}
function hideTooltip(): void {
    tooltip.value.show = false;
}

// 表达式是否包含配速相关单位
const paceContext = computed(() => {
    const expr = lastInput.value.toLowerCase();
    const hasTime = /\b(hour|min|sec|second)\b/.test(expr);
    const hasDist = /\bkm\b/.test(expr);
    return { hasTime, hasDist, isSpeed: hasTime && hasDist && expr.includes('/') };
});

// 输入是否包含统计分隔符 · 或空格
const isStatInput = computed(() => {
    return /\d\s+\d/.test(inputText.value);
});

// LCD 输入美化：将 ^n 转为 Unicode 上标显示
const supMap: Record<string, string> = {
    '0': '⁰', '1': '¹', '2': '²', '3': '³', '4': '⁴',
    '5': '⁵', '6': '⁶', '7': '⁷', '8': '⁸', '9': '⁹',
    '+': '⁺', '-': '⁻', '(': '⁽', ')': '⁾', '.': '·',
};
const displayInput = computed(() => {
    const t = inputText.value;
    // 先转义用户输入
    const esc = t.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
    const sup = esc.replace(/\^(\d+|\(.+\)|\S)/g, (_, c: string) => {
        return `<sup>${c}</sup>`;
    });
    if (openParens.value > 0) {
        return sup + '<span style="color:#b0b4b8">' + ')'.repeat(openParens.value) + '</span>';
    }
    return sup;
});

// 括号追踪：未闭合的 ( 数量
const openParens = computed(() => {
    const open = (inputText.value.match(/\(/g) || []).length;
    const close = (inputText.value.match(/\)/g) || []).length;
    return Math.max(0, open - close);
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
    if (isSpeed) return 'km/h';
    if (hasTime && !hasDist) return 'h';
    if (hasDist && !hasTime) return 'km';
    return '';
});

// ===== 键盘按键反馈 =====
const activeKey = ref<string | null>(null);
let audioCtx: AudioContext | null = null;

function navigateHistory(direction: number): void {
    if (history.value.length === 0) return;
    if (historyIdx.value === -1) {
        savedInput.value = inputText.value;
        historyIdx.value = 0;
    } else {
        const next = historyIdx.value + direction;
        if (next < 0) {
            historyIdx.value = -1;
            inputText.value = savedInput.value;
            savedInput.value = "";
            return;
        }
        if (next >= history.value.length) return;
        historyIdx.value = next;
    }
    inputText.value = history.value[historyIdx.value].input;
    nextTick(() => {
        const inp = document.querySelector('.screen-input-field') as HTMLInputElement | null;
        if (inp) inp.setSelectionRange(inp.value.length, inp.value.length);
    });
}

const keyMap: Record<string, string> = {
    '0': '0', '1': '1', '2': '2', '3': '3', '4': '4', '5': '5', '6': '6', '7': '7', '8': '8', '9': '9',
    '.': '.', ',': '.',
    '/': '÷', '*': '×', '-': '−', '+': '+',
    'Backspace': '⌫', 'Delete': '⌫',
    ' ': 'Space', 'Spacebar': 'Space',
    'Enter': '=', '=': '=',
    'Escape': 'C',
    '(': '(', ')': ')',
    '^': '^', '%': '%',
};

function playClick(): void {
    if (!audioCtx) {
        try { audioCtx = new (window.AudioContext || (window as any).webkitAudioContext)(); } catch { return; }
    }
    if (!audioCtx) return;
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

function onKeyDown(e: KeyboardEvent): void {
    const isInputFocused = document.activeElement?.tagName === 'INPUT';

    if (e.key === 'ArrowLeft' || e.key === 'ArrowRight') {
        if (!isInputFocused) {
            e.preventDefault();
            showStats.value = e.key === 'ArrowRight';
        }
        return;
    }

    const input = document.activeElement as HTMLInputElement | null;
    const isOurInput = isInputFocused && !!input?.closest('.calc-screen');

    // ArrowUp/ArrowDown: 历史记录滚动（仅输入框聚焦时）
    if ((e.key === 'ArrowUp' || e.key === 'ArrowDown') && isOurInput) {
        e.preventDefault();
        navigateHistory(e.key === 'ArrowUp' ? -1 : 1);
        return;
    }

    const mapped = keyMap[e.key];
    if (!mapped) return;

    if (mapped === 'C') {
        e.preventDefault();
        calcKeyTap('C');
        return;
    }

    if (mapped === '⌫') {
        e.preventDefault();
        activeKey.value = mapped;
        playClick();
        if (isOurInput && input && input.selectionStart !== null) {
            const pos = input.selectionStart;
            if (pos !== null && pos > 0) {
                const before = inputText.value.slice(0, pos - 1);
                const after = inputText.value.slice(pos);
                inputText.value = before + after;
                nextTick(() => {
                    input.setSelectionRange(pos - 1, pos - 1);
                });
            }
        } else {
            inputText.value = inputText.value.slice(0, -1);
        }
        return;
    }

    if (mapped === 'Space') {
        e.preventDefault();
        activeKey.value = mapped;
        playClick();
        inputText.value += ' ';
        return;
    }

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

    if (isOurInput) {
        activeKey.value = mapped;
        playClick();
        return;
    }

    e.preventDefault();
    activeKey.value = mapped;
    playClick();
    // "0" 替换逻辑：输入数字/小数点/字母/括号时替换初始0
    if (inputText.value === '0' && /^[\d.(]|[a-z]/i.test(mapped)) {
        inputText.value = mapped;
    } else if (mapped === ')' && openParens.value === 0) {
        // 无未闭合括号时忽略 )
        return;
    } else {
        inputText.value += mapped === '÷' ? '/' : mapped === '×' ? '*' : mapped === '−' ? '-' : mapped;
    }
}

function onKeyUp(e: KeyboardEvent): void {
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

// 计算器按键布局 (iPhone 风格，最后一列为高亮蓝色运算符)
const calcKeys: string[][] = [
    ['⌫', 'C', '%', '÷'],
    ['7', '8', '9', '×'],
    ['4', '5', '6', '−'],
    ['1', '2', '3', '+'],
    ['+/−', '0', '.', '='],
];
const calcFuncKeys: string[] = [];

function calcKeyTap(key: string): void {
    playClick();
    if (key === 'C') {
        if (inputText.value === '0') {
            calcClear();
            cAcReady.value = false;
        } else if (cAcReady.value) {
            // AC 已准备好 → 全清
            calcClear();
            cAcReady.value = false;
        } else {
            let v = inputText.value;
            let i = v.length;
            while (i > 0 && !/^[+\-*/^\u2212]$/.test(v[i - 1])) i--;
            if (i === 0) {
                inputText.value = '0';
                cAcReady.value = false;
            } else if (i === v.length) {
                // 末尾是运算符→仅切 AC，内容不变
                cAcReady.value = true;
            } else {
                inputText.value = v.slice(0, i);
                cAcReady.value = false;
            }
        }
    } else if (key === '⌫') {
        const input = document.querySelector('.screen-input-field') as HTMLInputElement | null;
        if (input && input.selectionStart !== null && input.selectionStart > 0) {
            const pos = input.selectionStart;
            if (pos !== null) {
                const before = inputText.value.slice(0, pos - 1);
                const after = inputText.value.slice(pos);
                inputText.value = before + after;
                nextTick(() => input.setSelectionRange(pos - 1, pos - 1));
            }
        } else {
            inputText.value = inputText.value.slice(0, -1);
        }
    } else if (key === 'Space') {
        inputText.value += ' ';
    } else if (key === '+/−') {
        const t = inputText.value.trim();
        if (t === '0' || t === '') return;
        // 如果是负数，去掉负号；否则加负号
        if (t.startsWith('-')) {
            inputText.value = t.slice(1);
        } else if (t.startsWith('−( ') && t.endsWith(' )')) {
            // 去掉外层括号包裹
            inputText.value = t.slice(3, -2).trim();
        } else if (!isNaN(Number(t)) && isFinite(Number(t))) {
            inputText.value = String(-Number(t));
        } else {
            // 表达式：包裹在 -( ... ) 中
            inputText.value = `−(${t})`;
        }
    } else if (key === '=') {
        if (calcMode.value === 'solve') {
            // 方程模式：仅插入一个 = 符号
            if (!inputText.value.includes('=')) {
                inputText.value = inputText.value === '0' ? '=' : inputText.value + '=';
            }
        } else {
            handleKeyboardSubmit();
        }
    } else if (key === '%') {
        if (inputText.value === '0') {
            inputText.value = '%';
        } else {
            inputText.value += '%';
        }
    } else if (key === '÷') {
        inputText.value += '/';
    } else if (key === '×') {
        inputText.value += '*';
    } else if (key === '−') {
        inputText.value += '-';
    } else {
        // "0" 替换逻辑：数字/小数点/字母替换初始0
        if (inputText.value === '0' && /^[\d.]|[a-z]/i.test(key)) {
            inputText.value = key;
        } else {
            inputText.value += key;
        }
    }
    // 非 C 键按下时取消 AC 就绪状态
    if (key !== 'C') cAcReady.value = false;
}

function calcFuncTap(_fn: string): void { }

function calcClear(): void {
    playClick();
    inputText.value = '0';
    errorMsg.value = '';
    displayResult.value = null;
    lastInput.value = '';
    lastResultValue.value = null;
    numbers.value = [];
    solveResult.value = null;
    solveSteps.value = [];
}

// 支持的数学函数提示
const functionHints: string[] = [
    "sin(x)", "cos(x)", "tan(x)",
    "asin(x)", "acos(x)", "atan(x)",
    "sind(x)", "cosd(x)", "tand(x)",
    "sinh(x)", "cosh(x)", "tanh(x)",
    "sqrt(x)", "cbrt(x)", "ln(x)", "lg(x)", "log(x)", "log2(x)",
    "pow(x,y)", "hypot(x,y)",
    "abs(x)", "sign(x)", "floor(x)", "ceil(x)", "round(x)",
    "mod(x,y)", "deg(x)", "rad(x)",
    "nCr(n,r)", "nPr(n,r)", "x!", "x%",
    "hex2dec(x)", "bin2dec(x)",
    "pi", "e", "1/x", "x^2", "x^3", "km", "Hour", "Min", "Second",
];

const hintTooltips: Record<string, string> = {
    "sin(x)": "正弦", "cos(x)": "余弦", "tan(x)": "正切",
    "asin(x)": "反正弦", "acos(x)": "反余弦", "atan(x)": "反正切",
    "sind(x)": "正弦(度)", "cosd(x)": "余弦(度)", "tand(x)": "正切(度)",
    "sinh(x)": "双曲正弦", "cosh(x)": "双曲余弦", "tanh(x)": "双曲正切",
    "sqrt(x)": "平方根 √", "cbrt(x)": "立方根 ∛",
    "ln(x)": "自然对数", "lg(x)": "常用对数(10)", "log(x)": "常用对数(10)", "log2(x)": "以2为底对数",
    "pow(x,y)": "x 的 y 次幂", "hypot(x,y)": "√(x²+y²)",
    "abs(x)": "绝对值", "sign(x)": "符号(±1/0)", "floor(x)": "向下取整", "ceil(x)": "向上取整", "round(x)": "四舍五入",
    "mod(x,y)": "取模", "deg(x)": "弧度→度", "rad(x)": "度→弧度",
    "x^y": "x 的 y 次幂",
    "nCr(n,r)": "组合数 C(n,r)", "nPr(n,r)": "排列数 P(n,r)", "x!": "阶乘", "x%": "百分比 ÷100",
    "hex2dec(x)": "十六进制→十进制", "bin2dec(x)": "二进制→十进制",
    "pi": "圆周率 π≈3.1416", "e": "自然常数 e≈2.7183",
    "log2": "以2为底对数", "e^": "e 的 x 次幂", "10^": "10 的 x 次幂",
    "1/x": "倒数", "x^2": "平方", "x^3": "立方",
    "x": "变量 x",
    "km": "千米 (=1) · 距离单位", "Hour": "小时 (=1) · 时间单位",
    "Min": "分钟 (=1/60h) · 时间单位",
    "(": "左括号", ")": "右括号", "2nd": "切换正/反函数",
    "y√x": "y 次根号", "Rand": "随机数 (0~1)",
    "y^x": "y 的 x 次幂", "2^x": "2 的 x 次幂",
    "logy": "以 y 为底对数", "asinh": "反双曲正弦", "acosh": "反双曲余弦", "atanh": "反双曲正切",
};

// ===== 动态预设函数（根据模式切换）=====
const standardHintsRad: string[] = [
    "2nd", "Rad", "(", ")", "x^2", "x^3", "x^y",
    "e^", "10^", "1/x", "sqrt", "cbrt", "y√x",
    "ln", "lg", "x!", "sin", "cos", "tan",
    "pi", "e", "Rand", "sinh", "cosh", "tanh",
    "abs", "nCr", "nPr",
];
const standardHintsDeg: string[] = [
    "2nd", "Rad", "(", ")", "x^2", "x^3", "x^y",
    "e^", "10^", "1/x", "sqrt", "cbrt", "y√x",
    "ln", "lg", "x!", "sind", "cosd", "tand",
    "pi", "e", "Rand", "sinh", "cosh", "tanh",
    "abs", "nCr", "nPr",
];
// 2nd 模式：三角→反三角，e^x→y^x，10^x→2^x，ln→logy，lg→log2
const standardHintsRadInv: string[] = [
    "2nd", "Rad", "(", ")", "x^2", "x^3", "x^y",
    "y^x", "2^x", "1/x", "sqrt", "cbrt", "y√x",
    "logy", "log2", "x!", "asin", "acos", "atan",
    "pi", "e", "Rand", "asinh", "acosh", "atanh",
    "abs", "nCr", "nPr",
];
const standardHintsDegInv: string[] = [
    "2nd", "Rad", "(", ")", "x^2", "x^3", "x^y",
    "y^x", "2^x", "1/x", "sqrt", "cbrt", "y√x",
    "logy", "log2", "x!", "asin", "acos", "atan",
    "pi", "e", "Rand", "asinh", "acosh", "atanh",
    "abs", "nCr", "nPr",
];

const solveHints: string[] = [
    "ax^2+bx+c=0", "ax+b=0", "x^2+px+q=0", "ax^2+bx=0",
    "ax^3+bx^2+cx+d=0", "a/x+b=c", "sqrt(ax+b)=c",
    "a^x=b", "ln(x)=a", "abs(x)=a",
    "sin(x)=a", "cos(x)=a", "tan(x)=a",
    "1/x", "x^2", "x^3", "x",
];

// 工具模式：配速单位预设
const toolHints: string[] = [
    "km", "Hour", "Min", "Second",
];

// 方程模式下仅用于输入变量的辅助按钮（非计算功能）
const inputHelperHints = new Set(['1/x', 'x', 'x^2', 'x^3']);

// 预设按钮去除 (x) 后缀节省空间，x^2→x²，sqrt/cbrt 用 KaTeX 渲染
function hintLabel(h: string): string {
    return h.replace(/\([^)]*\)/g, '')
        .replace(/\^2/g, '²').replace(/\^3/g, '³')
        .replace(/^sqrt$/, '√').replace(/^cbrt$/, '∛');
}
function hintLabelHtml(h: string): string {
    // KaTeX 数学公式渲染
    const katexMap: Record<string, string> = {
        'sqrt': '\\sqrt{\\phantom{0}}',
        'cbrt': '\\sqrt[3]{\\phantom{0}}',
        'y√x': '\\sqrt[y]{\\phantom{0}}',
        'x^y': 'x^{\\phantom{0}}',
        'e^': 'e^x',
        '10^': '10^x',
        'y^x': 'y^x',
        '2^x': '2^x',
        'x^2': 'x^2',
        'x^3': 'x^3',
    };
    if (katexMap[h]) {
        try { return katex.renderToString(katexMap[h], { throwOnError: false, displayMode: false }); } catch { /* fallback */ }
    }
    // fallback 给 KaTeX 失败或不在 map 中的
    if (h === 'sqrt') return '√';
    if (h === 'cbrt') return '∛';
    if (h === 'y√x') return 'ʸ√x';
    if (h === 'x^y') return 'xʸ';
    if (h === 'e^') return 'eˣ';
    if (h === '10^') return '10ˣ';
    if (h === 'y^x') return 'yˣ';
    if (h === '2^x') return '2ˣ';
    return hintLabel(h);
}

const HINT_ROW_COUNT = 7;

const emptyMessage = computed(() =>
    calcMode.value === 'solve'
        ? 'Enter equation and press Enter to solve'
        : 'Enter data to see statistics'
);

const displayHints = computed(() => {
    const cols = calcMode.value === 'solve' ? 4 : 5;
    const rows = calcMode.value === 'solve' ? 6 : 6;
    const total = rows * cols;
    let hints: string[];
    if (calcMode.value === 'solve') hints = solveHints;
    else if (calcMode.value === 'tools') hints = toolHints;
    else if (useDegrees.value) {
        hints = useInverse.value ? standardHintsDegInv : standardHintsDeg;
    } else {
        hints = useInverse.value ? standardHintsRadInv : standardHintsRad;
    }
    const padded: (string | null)[] = [...hints];
    while (padded.length < total) padded.push(null);
    return padded;
});

// 计算结果统计
const stats = computed((): StatsResult | null => {
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

const rankedData = computed((): RankedItem[] => {
    if (numbers.value.length === 0) return [];
    const N = numbers.value.length;
    const indexed = numbers.value.map((v, i) => ({ idx: i + 1, raw: v }));
    const sorted = [...indexed].sort((a, b) => b.raw - a.raw);
    let r = 0;
    let prev = NaN;
    return sorted.map((item) => {
        if (item.raw !== prev) { r++; prev = item.raw; }
        const pct = N > 1 ? ((N - r) / (N - 1)) * 100 : 100;
        return { ...item, rank: r, pct: Math.round(pct * 10) / 10 };
    });
});

const gradedData = computed((): GradedItem[] => {
    return rankedData.value.map(r => {
        let grade: string;
        if (r.pct >= aBound.value) grade = 'A';
        else if (r.pct >= bBound.value) grade = 'B';
        else if (r.pct >= cBound.value) grade = 'C';
        else grade = 'D';
        return { ...r, grade };
    });
});

const gradeCounts = computed(() => {
    const counts: Record<string, number> = { A: 0, B: 0, C: 0, D: 0 };
    gradedData.value.forEach(r => counts[r.grade]++);
    return counts;
});

const sortedGradeData = computed(() => {
    const data = [...gradedData.value];
    const key = gradeSortKey.value;
    const asc = gradeSortAsc.value;
    data.sort((a, b) => {
        let va: number | string;
        let vb: number | string;
        if (key === "grade") {
            const order: Record<string, number> = { A: 1, B: 2, C: 3, D: 4 };
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

function toggleGradeSort(key: "rank" | "idx" | "raw" | "pct" | "grade"): void {
    if (gradeSortKey.value === key) {
        gradeSortAsc.value = !gradeSortAsc.value;
    } else {
        gradeSortKey.value = key;
        gradeSortAsc.value = true;
    }
}

function sortArrowFor(key: string): string {
    if (gradeSortKey.value !== key) return '';
    return gradeSortAsc.value ? ' \u25B2' : ' \u25BC';
}

// 实时预览
const previewResult = computed((): { value: string } | null => {
    const input = inputText.value.trim();
    if (!input) return null;
    const val = evaluateSingle(input);
    return isNaN(val) ? null : { value: formatNum(val) };
});

// ===== 动态字号：监听结果变化 =====
watch([displayResult, previewResult], () => {
    adjustFontSize();
});

// 输入是 "0" 时，手动键入非运算符字符自动去掉前缀0；无效 ) 回退
watch(inputText, (val, prev) => {
    if (!prev) return;
    // 0前缀替换
    if (prev === '0' && val.length > 1 && val.startsWith('0') && /^[a-z(]/i.test(val[1])) {
        inputText.value = val.slice(1);
        return;
    }
    // 检测是否有新增的无效 )，回退
    const prevOpen = (prev.match(/\(/g) || []).length;
    const prevClose = (prev.match(/\)/g) || []).length;
    const valOpen = (val.match(/\(/g) || []).length;
    const valClose = (val.match(/\)/g) || []).length;
    if (valClose > valOpen && valClose > prevClose) {
        inputText.value = prev; // 回退
    }
});

onMounted(() => {
    window.addEventListener('resize', adjustFontSize);
});
onUnmounted(() => {
    window.removeEventListener('resize', adjustFontSize);
});

// ===== 方程求解（增强版：支持一次/二次/三次，含解题步骤）=====
const solveSteps = ref<any[]>([]);
const solveResult = ref<any>(null);

const renderedSteps = computed(() => {
    return solveSteps.value.map(step => ({
        ...step,
        html: renderMath(step.text),
    }));
});

function clearResults(): void {
    numbers.value = [];
    errorMsg.value = "";
    displayResult.value = null;
    lastResultValue.value = null;
    solveResult.value = null;
    solveSteps.value = [];
}

function clearHistory(): void {
    history.value = [];
    historyFilter.value = 'all';
}

// ===== 笛卡尔坐标系图表数据 =====
const showGraph = ref(false);

const graphData = computed(() => {
    const r = solveResult.value;
    if (!r || (r.type !== 'quadratic' && r.type !== 'linear' && r.type !== 'cubic')) return null;

    const W = 280, H = 220, pad = 40;
    // 获取方程系数
    let a = 0, b = 0, c = 0;
    if (r.type === 'quadratic') { a = r.a || 0; b = r.b || 0; c = r.c || 0; }
    else if (r.type === 'linear') { a = 0; b = r.b || 0; c = r.c || 0; }
    else if (r.type === 'cubic') { a = r.a || 0; b = r.b || 0; c = r.c || 0; }

    // 计算所有关键点的x坐标范围
    const realRoots: number[] = (r.solutions || [])
        .map((s: string) => parseFloat(String(s)))
        .filter((n: number) => !isNaN(n) && isFinite(n));

    const vertexX = a !== 0 ? -b / (2 * a) : 0;
    const keyX = [...realRoots, vertexX, 0].filter(n => isFinite(n));
    let xMin = Math.min(...keyX) - 2;
    let xMax = Math.max(...keyX) + 2;
    if (xMax - xMin < 4) { const mid = (xMin + xMax) / 2; xMin = mid - 3; xMax = mid + 3; }

    // 生成曲线点
    const f = (x: number) => a * x * x + b * x + c;
    const points: { x: number, y: number }[] = [];
    const steps = 200;
    for (let i = 0; i <= steps; i++) {
        const x = xMin + (xMax - xMin) * i / steps;
        const y = f(x);
        if (isFinite(y)) points.push({ x, y });
    }

    const yVals = points.map(p => p.y);
    let yMin = Math.min(...yVals);
    let yMax = Math.max(...yVals);
    const yPad = (yMax - yMin) * 0.15 || 2;
    yMin -= yPad;
    yMax += yPad;

    // 坐标映射函数
    const xToSvg = (x: number) => pad + (x - xMin) / (xMax - xMin) * (W - 2 * pad);
    const yToSvg = (y: number) => H - pad - (y - yMin) / (yMax - yMin) * (H - 2 * pad);

    // 生成SVG路径
    const pathD = points.map((p, i) => `${i === 0 ? 'M' : 'L'} ${xToSvg(p.x).toFixed(1)} ${yToSvg(p.y).toFixed(1)}`).join(' ');

    // 坐标轴刻度
    const xTicks: number[] = [];
    const xStep = Math.pow(10, Math.floor(Math.log10(xMax - xMin))) / 2;
    for (let x = Math.ceil(xMin / xStep) * xStep; x <= xMax; x += xStep) {
        if (Math.abs(x) < xStep * 0.01) xTicks.push(0);
        else xTicks.push(Math.round(x * 100) / 100);
    }
    const yTicks: number[] = [];
    const yStep = Math.pow(10, Math.floor(Math.log10(yMax - yMin))) / 2;
    for (let y = Math.ceil(yMin / yStep) * yStep; y <= yMax; y += yStep) {
        if (Math.abs(y) < yStep * 0.01) yTicks.push(0);
        else yTicks.push(Math.round(y * 100) / 100);
    }

    // 根和顶点的SVG坐标（含智能避让的标签偏移）
    const midX = (xMin + xMax) / 2;
    const rootPoints = realRoots.map((rx, i) => {
        const sx = xToSvg(rx), sy = yToSvg(0);
        // 标签避让：根在左半侧放左边，右半侧放右边；多个根时上下交替
        const side = rx < midX ? -1 : 1;
        const yOff = i % 2 === 0 ? -14 : 6;
        const xOff = side * 7;
        return { x: sx, y: sy, label: `x=${formatNum(rx)}`, dx: xOff, dy: yOff, anchor: side < 0 ? 'end' : 'start' };
    });
    const vertexPoint = a !== 0 ? (() => {
        const vx = xToSvg(vertexX), vy = yToSvg(f(vertexX));
        // 顶点标签：抛物线开口向上(a>0)放顶点下方，开口向下(a<0)放上方
        const below = a > 0;
        return { x: vx, y: vy, label: `(${formatNum(vertexX)},${formatNum(f(vertexX))})`, dx: 7, dy: below ? 14 : -14, anchor: 'start' };
    })() : null;
    const origin = { x: xToSvg(0), y: yToSvg(0) };
    const yIntercept = { x: xToSvg(0), y: yToSvg(c), label: `(0,${formatNum(c)})`, dx: -7, dy: c > 0 ? 14 : -14, anchor: 'end' };

    return { W, H, pad, xToSvg, yToSvg, pathD, xTicks, yTicks, rootPoints, vertexPoint, origin, yIntercept, xMin, xMax, yMin, yMax };
});

function fillFromHistory(item: HistoryItem): void {
    // 所有记录统一填充原输入表达式
    inputText.value = item.input;
    errorMsg.value = "";
}

function handleQuickPaste(): void {
    errorMsg.value = "";
    const raw = quickPasteText.value.trim();
    if (!raw) return;
    const tokens = splitTokens(raw);
    const nums: number[] = [];
    for (const token of tokens) {
        if (!token) continue;
        const val = evaluateSingle(token);
        if (isNaN(val)) {
            errorMsg.value = `"${token}": 请输入正确的表达式`;
            return;
        }
        nums.push(val);
    }
    if (nums.length === 0) {
        errorMsg.value = "未解析到有效的数字";
        return;
    }
    numbers.value = nums;
    addHistory("粘贴", raw.slice(0, 40) + (raw.length > 40 ? "…" : ""), nums);
    quickPasteText.value = "";
}

function copyToClipboard(text: unknown, idx: number): void {
    navigator.clipboard.writeText(String(text));
    copiedIdx.value = idx;
    setTimeout(() => (copiedIdx.value = -1), 1200);
}

const gradeTableCopied = ref(false);
function copyGradeTable(): void {
    const header = ["序号", "数值", "排名", "分位%", "等级"];
    const rows = sortedGradeData.value.map(r => [
        String(r.idx),
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

function insertHint(hint: string): void {
    playClick();
    if (calcMode.value === 'solve' && hint.includes('=')) {
        inputText.value = hint;
        return;
    }
    // 方程模式下的辅助输入按钮（1/x, x, x^2, x^3）仅插入字面文本，不做计算转换
    if (calcMode.value === 'solve' && inputHelperHints.has(hint)) {
        const trimmed = inputText.value.trim();
        inputText.value = trimmed ? trimmed + ' ' + hint : hint;
        return;
    }
    const trimmed = inputText.value.trim();
    const isNumber = trimmed !== "" && !isNaN(Number(trimmed)) && isFinite(Number(trimmed));

    if (hint === 'mod') {
        if (isNumber) {
            inputText.value = `mod(${trimmed},`;
        } else if (trimmed) {
            let wrap = trimmed;
            if (trimmed.startsWith('(') && trimmed.endsWith(')')) {
                const inner = trimmed.slice(1, -1);
                let depth = 0, balanced = true;
                for (const ch of inner) {
                    if (ch === '(') depth++;
                    else if (ch === ')') { depth--; if (depth < 0) { balanced = false; break; } }
                }
                if (!(balanced && depth === 0)) wrap = `(${trimmed})`;
            } else {
                wrap = `(${trimmed})`;
            }
            inputText.value = `mod${wrap},`;
        } else {
            inputText.value = 'mod(';
        }
        return;
    }

    if (hint === 'x^y') {
        if (isNumber) {
            inputText.value = trimmed + '^';
        } else if (trimmed) {
            let wrap = trimmed;
            if (trimmed.startsWith('(') && trimmed.endsWith(')')) {
                const inner = trimmed.slice(1, -1);
                let depth = 0, balanced = true;
                for (const ch of inner) {
                    if (ch === '(') depth++;
                    else if (ch === ')') { depth--; if (depth < 0) { balanced = false; break; } }
                }
                if (!(balanced && depth === 0)) wrap = `(${trimmed})`;
            } else {
                wrap = `(${trimmed})`;
            }
            inputText.value = `${wrap}^`;
        } else {
            inputText.value = '^';
        }
        return;
    }

    if (hint === 'e^' || hint === '10^') {
        const base = hint === 'e^' ? 'e' : '10';
        if (isNumber) {
            inputText.value = `${base}^${trimmed}`;
        } else if (trimmed) {
            // 检查是否已被一对完整括号包裹
            let wrap = trimmed;
            if (trimmed.startsWith('(') && trimmed.endsWith(')')) {
                const inner = trimmed.slice(1, -1);
                let depth = 0, balanced = true;
                for (const ch of inner) {
                    if (ch === '(') depth++;
                    else if (ch === ')') { depth--; if (depth < 0) { balanced = false; break; } }
                }
                if (balanced && depth === 0) wrap = trimmed; // 已完整包裹，不重复
                else wrap = `(${trimmed})`;
            } else {
                wrap = `(${trimmed})`;
            }
            inputText.value = `${base}^${wrap}`;
        } else {
            inputText.value = `${base}^`;
        }
        return;
    }


    if (hint === '(') {
        if (inputText.value === '0') {
            inputText.value = '(';
        } else {
            inputText.value += '(';
        }
        return;
    }
    if (hint === ')') {
        if (openParens.value > 0) {
            inputText.value += ')';
        }
        return;
    }
    if (hint === '2nd') {
        useInverse.value = !useInverse.value;
        return;
    }
    if (hint === 'Rad') {
        useDegrees.value = !useDegrees.value;
        return;
    }

    if (hint === 'y√x') {
        if (isNumber) {
            inputText.value = `${trimmed}^(1/`;
        } else if (trimmed) {
            let wrap = trimmed;
            if (trimmed.startsWith('(') && trimmed.endsWith(')')) {
                const inner = trimmed.slice(1, -1);
                let depth = 0, balanced = true;
                for (const ch of inner) {
                    if (ch === '(') depth++;
                    else if (ch === ')') { depth--; if (depth < 0) { balanced = false; break; } }
                }
                if (!(balanced && depth === 0)) wrap = `(${trimmed})`;
            } else {
                wrap = `(${trimmed})`;
            }
            inputText.value = `${wrap}^(1/`;
        } else {
            inputText.value = '^(1/';
        }
        return;
    }

    if (hint === 'sqrt' || hint === 'cbrt') {
        const fn = hint;
        if (isNumber) {
            inputText.value = `${fn}(${trimmed})`;
        } else if (trimmed) {
            // 检测是否已被一对完整括号包裹，避免重复
            let wrap = trimmed;
            if (trimmed.startsWith('(') && trimmed.endsWith(')')) {
                const inner = trimmed.slice(1, -1);
                let depth = 0, balanced = true;
                for (const ch of inner) {
                    if (ch === '(') depth++;
                    else if (ch === ')') { depth--; if (depth < 0) { balanced = false; break; } }
                }
                if (balanced && depth === 0) wrap = trimmed;
                else wrap = `(${trimmed})`;
            } else {
                wrap = `(${trimmed})`;
            }
            inputText.value = `${fn}${wrap}`;
        } else {
            inputText.value = `${fn}(`;
        }
        return;
    }

    if (hint === 'Rand') {
        const r = Math.random();
        inputText.value = inputText.value === '0' ? formatNum(r) : (trimmed ? trimmed + ` ${formatNum(r)}` : formatNum(r));
        playClick();
        return;
    }

    if (hint === 'y^x') {
        if (isNumber) {
            inputText.value = `${trimmed}^(`;
        } else if (trimmed) {
            // 包裹表达式
            let wrap = trimmed;
            if (trimmed.startsWith('(') && trimmed.endsWith(')')) {
                const inner = trimmed.slice(1, -1);
                let depth = 0, balanced = true;
                for (const ch of inner) {
                    if (ch === '(') depth++;
                    else if (ch === ')') { depth--; if (depth < 0) { balanced = false; break; } }
                }
                if (!(balanced && depth === 0)) wrap = `(${trimmed})`;
            } else {
                wrap = `(${trimmed})`;
            }
            inputText.value = `${wrap}^(`;
        } else {
            inputText.value = '^(';
        }
        return;
    }

    if (hint === '2^x') {
        if (isNumber) {
            inputText.value = `2^${trimmed}`;
        } else if (trimmed) {
            let wrap = trimmed;
            if (trimmed.startsWith('(') && trimmed.endsWith(')')) {
                const inner = trimmed.slice(1, -1);
                let depth = 0, balanced = true;
                for (const ch of inner) {
                    if (ch === '(') depth++;
                    else if (ch === ')') { depth--; if (depth < 0) { balanced = false; break; } }
                }
                if (!(balanced && depth === 0)) wrap = `(${trimmed})`;
            } else {
                wrap = `(${trimmed})`;
            }
            inputText.value = `2^${wrap}`;
        } else {
            inputText.value = '2^';
        }
        return;
    }

    if (hint === 'logy') {
        if (isNumber) {
            inputText.value = `log(${trimmed},`;
        } else if (trimmed) {
            let wrap = trimmed;
            if (trimmed.startsWith('(') && trimmed.endsWith(')')) {
                const inner = trimmed.slice(1, -1);
                let depth = 0, balanced = true;
                for (const ch of inner) {
                    if (ch === '(') depth++;
                    else if (ch === ')') { depth--; if (depth < 0) { balanced = false; break; } }
                }
                if (!(balanced && depth === 0)) wrap = `(${trimmed})`;
            } else {
                wrap = `(${trimmed})`;
            }
            inputText.value = `log${wrap},`;
        } else {
            inputText.value = 'log(';
        }
        return;
    }

    if (hint === 'log2') {
        if (isNumber) {
            inputText.value = `log2(${trimmed})`;
        } else if (trimmed) {
            let wrap = trimmed;
            if (trimmed.startsWith('(') && trimmed.endsWith(')')) {
                const inner = trimmed.slice(1, -1);
                let depth = 0, balanced = true;
                for (const ch of inner) {
                    if (ch === '(') depth++;
                    else if (ch === ')') { depth--; if (depth < 0) { balanced = false; break; } }
                }
                if (!(balanced && depth === 0)) wrap = `(${trimmed})`;
            } else {
                wrap = `(${trimmed})`;
            }
            inputText.value = `log2${wrap}`;
        } else {
            inputText.value = 'log2(';
        }
        return;
    }

    // π 和 e：替换默认 0
    if (hint === 'pi') { inputText.value = inputText.value === '0' ? 'pi' : (trimmed ? trimmed + ' pi' : 'pi'); return; }
    if (hint === 'e') { inputText.value = inputText.value === '0' ? 'e' : (trimmed ? trimmed + ' e' : 'e'); return; }

    // 配速单位：替换默认 0
    if (hint === 'km' || hint === 'Hour' || hint === 'Min' || hint === 'Second') {
        inputText.value = inputText.value === '0' ? hint : (trimmed ? trimmed + ' ' + hint : hint);
        return;
    }

    // 反双曲函数（包裹当前输入）
    const singleArgFns = ['sin', 'cos', 'tan', 'sind', 'cosd', 'tand',
        'sinh', 'cosh', 'tanh', 'asin', 'acos', 'atan',
        'asinh', 'acosh', 'atanh', 'ln', 'lg', 'abs'];
    if (singleArgFns.includes(hint)) {
        if (isNumber) {
            inputText.value = `${hint}(${trimmed})`;
        } else if (trimmed) {
            // 检测是否已被一对完整括号包裹，避免重复
            let wrap = trimmed;
            if (trimmed.startsWith('(') && trimmed.endsWith(')')) {
                const inner = trimmed.slice(1, -1);
                let depth = 0, balanced = true;
                for (const ch of inner) {
                    if (ch === '(') depth++;
                    else if (ch === ')') { depth--; if (depth < 0) { balanced = false; break; } }
                }
                if (balanced && depth === 0) wrap = trimmed;
                else wrap = `(${trimmed})`;
            } else {
                wrap = `(${trimmed})`;
            }
            inputText.value = `${hint}${wrap}`;
        } else {
            inputText.value = `${hint}(`;
        }
        return;
    }

    // 双参数函数：nCr, nPr
    if (hint === 'nCr' || hint === 'nPr') {
        if (isNumber) {
            inputText.value = `${hint}(${trimmed},`;
        } else if (trimmed) {
            let wrap = trimmed;
            if (trimmed.startsWith('(') && trimmed.endsWith(')')) {
                const inner = trimmed.slice(1, -1);
                let depth = 0, balanced = true;
                for (const ch of inner) {
                    if (ch === '(') depth++;
                    else if (ch === ')') { depth--; if (depth < 0) { balanced = false; break; } }
                }
                if (!(balanced && depth === 0)) wrap = `(${trimmed})`;
            } else {
                wrap = `(${trimmed})`;
            }
            inputText.value = `${hint}${wrap},`;
        } else {
            inputText.value = `${hint}(`;
        }
        return;
    }

    if (hint.includes("(")) {
        if (isNumber) {
            if (hint.includes(",")) {
                inputText.value = hint.replace(/\([^,)]+/, `(${trimmed}`);
            } else {
                inputText.value = hint.replace(/\([^)]*\)/, `(${trimmed})`);
            }
        } else {
            inputText.value = trimmed ? trimmed + " " + hint : hint;
        }
    } else {
        if (isNumber && hint === "x!") {
            inputText.value = trimmed + "!";
        } else if (isNumber && hint === "x%") {
            inputText.value = trimmed + "%";
        } else if (hint === "1/x") {
            if (isNumber) {
                inputText.value = `1/${trimmed}`;
            } else if (trimmed) {
                // 检测是否已被一对完整括号包裹，避免重复
                let wrap = trimmed;
                if (trimmed.startsWith('(') && trimmed.endsWith(')')) {
                    const inner = trimmed.slice(1, -1);
                    let depth = 0, balanced = true;
                    for (const ch of inner) {
                        if (ch === '(') depth++;
                        else if (ch === ')') { depth--; if (depth < 0) { balanced = false; break; } }
                    }
                    if (balanced && depth === 0) wrap = trimmed; // 已完整包裹
                    else wrap = `(${trimmed})`;
                } else {
                    wrap = `(${trimmed})`;
                }
                inputText.value = `1/${wrap}`;
            } else {
                inputText.value = '1/';
            }
        } else if (hint === "x^2") {
            inputText.value = isNumber ? trimmed + '^2' : `(${trimmed})^2`;
        } else if (hint === "x^3") {
            inputText.value = isNumber ? trimmed + '^3' : `(${trimmed})^3`;
        } else {
            inputText.value = trimmed ? trimmed + " " + hint : hint;
        }
    }
}

function handleKeyboardSubmit(): void {
    errorMsg.value = "";
    // 自动闭合未配对的括号
    if (openParens.value > 0) {
        inputText.value += ')'.repeat(openParens.value);
    }
    const input = inputText.value.trim();

    if (!input && lastResultValue.value !== null) {
        return;
    }
    if (!input) return;

    // ===== 方程求解模式 =====
    if (calcMode.value === 'solve' && input.includes('=')) {
        try {
            const { steps, result } = solveEq(input, useDegrees.value);
            solveSteps.value = steps;
            solveResult.value = result;
            numbers.value = result.solutions.map((s: string) => {
                const match = String(s).match(/^([-+]?\d+\.?\d*)/);
                return match ? Number(match[1]) : NaN;
            }).filter((n: number) => !isNaN(n));
            displayResult.value = result.display.replace(/\n/g, '  |  ');
            lastInput.value = input;
            lastResultValue.value = numbers.value.length > 0 ? numbers.value[0] : null;
            addHistory("SOLVE", input, numbers.value.filter(n => isFinite(n)));
            inputText.value = "0";
            return;
        } catch (err: any) {
            errorMsg.value = err.message || String(err);
            return;
        }
    }

    // ===== 工具模式：必须包含物理单位 =====
    if (calcMode.value === 'tools' && !/\b(km|hour|min|second|sec)\b/i.test(input)) {
        errorMsg.value = "工具模式需要输入物理单位（km, Hour, Min, Second）";
        return;
    }

    // ===== 标准计算模式 =====
    let expr = input;
    if (lastResultValue.value !== null && /^[+\-*/^%]/.test(input)) {
        expr = String(lastResultValue.value) + ' ' + input;
    }

    displayResult.value = null;

    // 若表达式含物理单位，整体求值，避免按空格分割破坏语义
    const hasUnit = /\b(km|hour|min|sec|second)\b/i.test(expr);
    const rawTokens = hasUnit ? [expr] : splitTokens(expr);
    const nums: number[] = [];
    for (const token of rawTokens) {
        if (!token) continue;
        const val = evaluateSingle(token);
        if (isNaN(val)) {
            errorMsg.value = "请输入正确的表达式";
            return;
        }
        nums.push(val);
    }
    if (nums.length === 0) {
        errorMsg.value = "未解析到有效的数字";
        return;
    }
    if (lastResultValue.value !== null && !/^[+\-*/^%]/.test(input)) {
        if (rawTokens.length > 1 || nums.length > 1) {
            nums.unshift(lastResultValue.value);
            expr = String(lastResultValue.value) + ', ' + input;
        }
    }
    numbers.value = nums;
    addHistory("键盘", expr, nums);
    lastInput.value = expr;
    const sum = nums.reduce((a, b) => a + b, 0);
    lastResultValue.value = nums.length > 1 ? sum : nums[0];
    displayResult.value = nums.length > 1 ? formatNum(sum) : formatNum(nums[0]);
    inputText.value = "";
    historyIdx.value = -1;  // 计算后重置历史浏览位置
}

function addHistory(source: string, input: string, nums: number[]): void {
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

</script>

<template>
    <div class="page">
        <div class="drag-bar"></div>
        <div class="calc-dual" @touchstart.passive="onTouchStart" @touchend.passive="onTouchEnd">
            <!-- ====== 左侧：计算器 ====== -->
            <div class="calc-body" :class="{ 'panel-hidden': showStats }">
                <div class="calc-top-bar">
                    <span class="calc-brand">AnyCalculator</span>
                    <span class="calc-model">SC-100</span>
                </div>

                <div class="calc-screen">
                    <div class="screen-status">
                        <span class="status-mode">{{ calcMode === 'solve' ? 'SOLVE' : (isStatInput ? 'STAT' :
                            paceContext.isSpeed ? 'PACE' : 'COMP') }}</span>
                        <span v-if="useDegrees" class="status-deg">DEG</span>
                        <span v-else class="status-deg">RAD</span>
                        <span v-if="useInverse" class="status-inv">INV</span>
                        <span v-if="stats" class="status-stat">STAT</span>
                        <span class="status-mem" v-if="history.length">M</span>
                        <span class="status-bat">▮▮▮</span>
                    </div>
                    <div class="screen-expr"
                        :class="{ 'screen-hidden': !(displayResult && lastInput) && calcMode !== 'solve' }">
                        {{ lastInput || '\u00A0' }}
                    </div>
                    <div class="screen-input">
                        <div class="input-wrapper">
                            <span class="input-display" :class="{ 'input-placeholder': !inputText && !displayResult }"
                                aria-hidden="true" v-html="inputText ? displayInput : (!displayResult ? (calcMode === 'solve' ? '输入方程...' :
                                    '输入表达式...') : '&nbsp;')
                                    "></span>
                            <input v-model="inputText" class="screen-input-field"
                                :placeholder="displayResult ? '' : (calcMode === 'solve' ? '输入方程...' : '输入表达式...')"
                                @keydown.space.prevent="inputText += ' '" @keyup.enter="handleKeyboardSubmit" />
                        </div>
                    </div>
                    <div class="screen-output">
                        <div class="output-row" ref="outputRow">
                            <span v-show="displayResult" ref="outputValueRef" class="output-value"
                                :style="{ fontSize: outputFontSize + 'px' }">{{ displayResult }}<span v-if="resultUnit"
                                    class="output-unit" :style="{ fontSize: Math.max(outputFontSize * 0.7, 9) + 'px' }">
                                    {{ resultUnit }}</span></span>
                            <span v-show="!displayResult && previewResult" class="output-value dim">{{
                                previewResult?.value || '\u00A0' }}</span>
                            <span v-show="displayResult && paceText" class="output-pace" title="配速">{{ paceText
                                }}</span>
                        </div>
                        <span v-show="errorMsg" class="output-error">{{ errorMsg }}</span>
                    </div>
                    <div class="screen-stats" :class="{ 'screen-hidden': !stats && !solveResult }">
                        <!-- 统计模式 -->
                        <template v-if="stats && !solveResult">
                            <span>n={{ stats.count }}</span>
                            <span>Σ={{ formatNum(stats.sum) }}</span>
                            <span>x̄={{ formatNum(stats.avg) }}</span>
                            <span>σ={{ formatNum(stats.stddev) }}</span>
                            <span>min={{ formatNum(stats.min) }}</span>
                            <span>max={{ formatNum(stats.max) }}</span>
                        </template>
                        <!-- 方程模式 -->
                        <template v-else-if="solveResult && solveResult.type === 'quadratic'">
                            <span>Δ={{ formatNum(solveResult.delta) }}</span>
                            <span v-if="solveResult.delta && solveResult.delta > 0">两实根</span>
                            <span v-else-if="solveResult.delta && solveResult.delta < 0">共轭复根</span>
                            <span v-else>重根</span>
                            <span v-if="solveResult.a && solveResult.b">顶点({{
                                formatNum(-solveResult.b / (2 * solveResult.a)) }}, {{ formatNum(solveResult.a ?
                                    solveResult.c! - solveResult.b! * solveResult.b! / (4 * solveResult.a) : 0) }})</span>
                        </template>
                    </div>
                </div>

                <!-- ===== 功能切换按钮行 ===== -->
                <div class="mode-toggle-row">
                    <button class="mode-btn mode-standard" :class="{ active: calcMode === 'standard' }"
                        @click="calcMode = 'standard'; activeTab = 'basic'; playClick()" title="标准计算">
                        <span class="mode-icon">📐</span>标准
                    </button>
                    <button class="mode-btn mode-solve" :class="{ active: calcMode === 'solve' }"
                        @click="calcMode = 'solve'; activeTab = 'equation'; playClick()" title="方程求解">
                        <span class="mode-icon">🔢</span>方程
                    </button>
                    <button class="mode-btn mode-tools" :class="{ active: calcMode === 'tools' }"
                        @click="calcMode = 'tools'; activeTab = 'tools'; playClick()" title="配速工具">
                        <span class="mode-icon">🔧</span>工具
                    </button>
                </div>

                <!-- ===== 预设函数矩阵（动态，固定高度）===== -->
                <div class="calc-hints-area" :class="{ 'hints-4col': calcMode === 'solve' }">
                    <template v-for="(h, i) in displayHints" :key="i">
                        <span v-if="h" class="hint-tag" :class="{
                            'hint-pace': paceHints.has(h),
                            'hint-solve': calcMode === 'solve' && !inputHelperHints.has(h),
                            'hint-input': calcMode === 'solve' && inputHelperHints.has(h),
                            'hint-active': (h === '2nd' && useInverse) || (h === 'Rad' && !useDegrees),
                        }" @click="insertHint(h)" @mouseenter="showTooltip($event, hintTooltips[h] || h)"
                            @mouseleave="hideTooltip" v-html="hintLabelHtml(h)"></span>
                        <span v-else class="hint-tag hint-empty"></span>
                    </template>
                </div>

                <div class="calc-keypad">
                    <div class="calc-grid">
                        <template v-for="row in calcKeys" :key="row.join('')">
                            <button v-for="key in row" :key="key" class="calc-btn" :class="{
                                'calc-num': (key >= '0' && key <= '9') || key === '.',
                                'calc-op': ['÷', '×', '−', '+'].includes(key),
                                'calc-equals': key === '=',
                                'calc-pct': key === '%',
                                'calc-sign': key === '+/−',
                                'calc-clear': key === 'C',
                                'calc-del': key === '⌫',
                                'calc-pressed': activeKey === key,
                            }" @click="calcKeyTap(key)">{{ key === 'C' ? (inputText === '0' || cAcReady ? 'AC' : 'C') :
                                key
                            }}</button>
                        </template>
                    </div>
                    <div class="calc-bottom-area">
                        <div class="calc-action-row" :class="{ 'has-detail': stats }">
                            <button v-if="calcMode !== 'solve'" class="calc-btn calc-space"
                                :class="{ 'calc-pressed': activeKey === 'Space' }"
                                @click="calcKeyTap('Space')">SPACE</button>
                            <button v-if="calcMode === 'solve'" class="calc-btn calc-solve-btn"
                                @click="playClick(); handleKeyboardSubmit()">SOLVE</button>
                            <button v-if="stats" class="calc-btn calc-detail" @click="showStats = true">DETAIL</button>
                        </div>
                    </div>
                </div>
            </div>

            <!-- ====== 右侧：统计信息面板 ====== -->
            <div class="calc-info" :class="{ 'panel-hidden': !showStats }">
                <div class="info-top-bar">
                    <span class="info-brand">{{ calcMode === 'solve' && solveSteps.length > 0 ? 'SOLVE' : 'STAT'
                        }}</span>
                    <button class="info-back-btn" @click="showStats = false">← 返回</button>
                </div>
                <div class="info-lcd">
                    <!-- ===== 解题过程（求解模式）===== -->
                    <div v-if="calcMode === 'solve' && solveSteps.length > 0" class="info-solve">
                        <div class="info-title">📐 解题过程</div>
                        <div class="solve-steps">
                            <div v-for="(step, i) in renderedSteps" :key="i" class="solve-step"
                                :class="{ 'solve-step-hl': step.hl }">
                                <span class="solve-step-num">{{ i + 1 }}</span>
                                <span class="solve-step-text" v-html="step.html"></span>
                            </div>
                        </div>
                        <!-- 笛卡尔坐标系图表 -->
                        <div v-if="graphData" class="graph-section">
                            <div class="graph-toggle" @click="showGraph = !showGraph">
                                📈 函数图像 {{ showGraph ? '▾' : '▸' }}
                            </div>
                            <svg v-show="showGraph" :viewBox="`0 0 ${graphData.W} ${graphData.H}`"
                                class="cartesian-graph" xmlns="http://www.w3.org/2000/svg">
                                <!-- 网格线 -->
                                <line v-for="tx in graphData.xTicks" :key="'gx' + tx" :x1="graphData.xToSvg(tx)"
                                    :y1="graphData.pad" :x2="graphData.xToSvg(tx)" :y2="graphData.H - graphData.pad"
                                    stroke="#d8dbde" stroke-width="0.5" />
                                <line v-for="ty in graphData.yTicks" :key="'gy' + ty" :x1="graphData.pad"
                                    :y1="graphData.yToSvg(ty)" :x2="graphData.W - graphData.pad"
                                    :y2="graphData.yToSvg(ty)" stroke="#d8dbde" stroke-width="0.5" />
                                <!-- 坐标轴 -->
                                <line :x1="graphData.pad" :y1="graphData.yToSvg(0)" :x2="graphData.W - graphData.pad"
                                    :y2="graphData.yToSvg(0)" stroke="#8b9094" stroke-width="1.5" />
                                <line :x1="graphData.xToSvg(0)" :y1="graphData.pad" :x2="graphData.xToSvg(0)"
                                    :y2="graphData.H - graphData.pad" stroke="#8b9094" stroke-width="1.5" />
                                <!-- 箭头 -->
                                <polygon
                                    :points="`${graphData.W - graphData.pad},${graphData.yToSvg(0)} ${graphData.W - graphData.pad - 6},${graphData.yToSvg(0) - 3} ${graphData.W - graphData.pad - 6},${graphData.yToSvg(0) + 3}`"
                                    fill="#8b9094" />
                                <polygon
                                    :points="`${graphData.xToSvg(0)},${graphData.pad} ${graphData.xToSvg(0) - 3},${graphData.pad + 6} ${graphData.xToSvg(0) + 3},${graphData.pad + 6}`"
                                    fill="#8b9094" />
                                <!-- 曲线 -->
                                <path :d="graphData.pathD" fill="none" stroke="#5b8def" stroke-width="2"
                                    stroke-linejoin="round" />
                                <!-- Y截距 -->
                                <circle v-if="graphData.yIntercept" :cx="graphData.yIntercept.x"
                                    :cy="graphData.yIntercept.y" r="4" fill="#f0a050" stroke="#fff" stroke-width="1" />
                                <text v-if="graphData.yIntercept" :x="graphData.yIntercept.x + graphData.yIntercept.dx"
                                    :y="graphData.yIntercept.y + graphData.yIntercept.dy"
                                    :text-anchor="graphData.yIntercept.anchor" font-size="9" fill="#5a6064">{{
                                        graphData.yIntercept.label }}</text>
                                <!-- 根（红色） -->
                                <template v-for="(rp, i) in graphData.rootPoints" :key="'r' + i">
                                    <circle :cx="rp.x" :cy="rp.y" r="5" fill="#dc2626" stroke="#fff"
                                        stroke-width="1.5" />
                                    <text :x="rp.x + rp.dx" :y="rp.y + rp.dy" :text-anchor="rp.anchor" font-size="9"
                                        fill="#b03030">{{ rp.label }}</text>
                                </template>
                                <!-- 顶点（蓝色） -->
                                <template v-if="graphData.vertexPoint">
                                    <circle :cx="graphData.vertexPoint.x" :cy="graphData.vertexPoint.y" r="5"
                                        fill="#5b8def" stroke="#fff" stroke-width="1.5" />
                                    <text :x="graphData.vertexPoint.x + graphData.vertexPoint.dx"
                                        :y="graphData.vertexPoint.y + graphData.vertexPoint.dy"
                                        :text-anchor="graphData.vertexPoint.anchor" font-size="9" fill="#4a7de0">{{
                                            graphData.vertexPoint.label }}</text>
                                </template>
                                <!-- 原点标签 -->
                                <text :x="graphData.xToSvg(0) - 4" :y="graphData.yToSvg(0) + 14" text-anchor="end"
                                    font-size="8" fill="#8b9094">O</text>
                            </svg>
                        </div>
                        <div class="solve-actions">
                            <button class="info-clear-btn info-clear-sm"
                                @click="solveSteps = []; solveResult = null; showStats = false">清除</button>
                            <button class="info-back-btn" @click="showStats = false">← 返回</button>
                        </div>
                    </div>

                    <div v-if="!stats && history.length === 0 && !(calcMode === 'solve' && solveSteps.length > 0)"
                        class="info-empty">
                        <span class="info-empty-icon">{{ calcMode === 'solve' ? '🔢' : '📊' }}</span>
                        <p>{{ emptyMessage }}</p>
                    </div>

                    <div v-if="stats && !(calcMode === 'solve' && solveSteps.length > 0)" class="info-stats">
                        <div class="info-title">统计结果</div>
                        <!-- 样本概况 -->
                        <div class="stat-group">
                            <div class="stat-group-label">样本概况</div>
                            <div class="info-grid info-grid-2col">
                                <div class="info-item" @click="copyToClipboard(stats.count, 0)">
                                    <span class="info-label">个数</span>
                                    <span class="info-val">{{ stats.count }}</span>
                                </div>
                                <div class="info-item" @click="copyToClipboard(formatNum(stats.sum), 1)">
                                    <span class="info-label">总和</span>
                                    <span class="info-val">{{ formatNum(stats.sum) }}</span>
                                </div>
                            </div>
                        </div>
                        <!-- 集中趋势 -->
                        <div class="stat-group">
                            <div class="stat-group-label">集中趋势</div>
                            <div class="info-grid info-grid-2col">
                                <div class="info-item" @click="copyToClipboard(formatNum(stats.avg), 4)">
                                    <span class="info-label">平均值</span>
                                    <span class="info-val">{{ formatNum(stats.avg) }}</span>
                                </div>
                                <div class="info-item" @click="copyToClipboard(formatNum(stats.median), 5)">
                                    <span class="info-label">中位数</span>
                                    <span class="info-val">{{ formatNum(stats.median) }}</span>
                                </div>
                            </div>
                        </div>
                        <!-- 离散程度 -->
                        <div class="stat-group">
                            <div class="stat-group-label">离散程度</div>
                            <div class="info-grid info-grid-4col">
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
                        </div>
                        <button class="info-clear-btn" @click="clearResults">清除结果</button>
                    </div>

                    <div class="info-grade"
                        v-if="stats && rankedData.length > 0 && !(calcMode === 'solve' && solveSteps.length > 0)">
                        <div class="info-title" @click="showGrade = !showGrade" style="cursor:pointer">
                            等级评定 {{ showGrade ? '▾' : '▸' }}
                        </div>
                        <div v-show="showGrade">
                            <div class="grade-note">
                                📌 等级标准：<br />相对最高分（最高分=100%），A≥{{ aBound }}% | B≥{{ bBound }}% | C≥{{ cBound }}% | D＜{{
                                    cBound }}%
                            </div>
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
                                            <th @click="toggleGradeSort('idx')">序{{ sortArrowFor("idx") }}</th>
                                            <th @click="toggleGradeSort('rank')">#{{ sortArrowFor("rank") }}</th>
                                            <th @click="toggleGradeSort('raw')">值{{ sortArrowFor("raw") }}</th>
                                            <th @click="toggleGradeSort('pct')">%{{ sortArrowFor("pct") }}</th>
                                            <th @click="toggleGradeSort('grade')">等{{ sortArrowFor("grade") }}</th>
                                        </tr>
                                    </thead>
                                    <tbody>
                                        <tr v-for="r in sortedGradeData" :key="r.idx" :class="'grade-' + r.grade">
                                            <td>{{ r.idx }}</td>
                                            <td class="col-rank">#{{ r.rank }}</td>
                                            <td>{{ formatNum(r.raw) }}</td>
                                            <td>{{ r.pct }}%</td>
                                            <td class="col-grade">{{ r.grade }}</td>
                                        </tr>
                                    </tbody>
                                </table>
                            </div>
                            <button class="copy-table-btn" @click="copyGradeTable">
                                {{ gradeTableCopied ? '✓ 已复制' : '复制表格' }}
                            </button>
                        </div>
                    </div>

                    <div v-if="history.length > 0 && !(calcMode === 'solve' && solveSteps.length > 0)"
                        class="info-history">
                        <div class="info-title">历史记录</div>
                        <div class="history-filters">
                            <button class="history-filter-btn" :class="{ active: historyFilter === 'all' }"
                                @click="historyFilter = 'all'">全部</button>
                            <button class="history-filter-btn" :class="{ active: historyFilter === 'calc' }"
                                @click="historyFilter = 'calc'">算术</button>
                            <button class="history-filter-btn" :class="{ active: historyFilter === 'solve' }"
                                @click="historyFilter = 'solve'">方程</button>
                            <button class="history-filter-btn" :class="{ active: historyFilter === 'stat' }"
                                @click="historyFilter = 'stat'">工具</button>
                            <button class="history-clear-btn" @click="clearHistory" title="清除全部历史">🗑</button>
                        </div>
                        <div class="history-list">
                            <div v-for="item in filteredHistory" :key="item.id" class="history-item"
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
            <!-- 滑动指示点（仅移动端显示）-->
            <div class="swipe-hint">
                <span class="swipe-dot" :class="{ active: !showStats }" @click="showStats = false"></span>
                <span class="swipe-dot" :class="{ active: showStats }" @click="showStats = true"></span>
            </div>
        </div>
        <!-- 底部Tab导航 -->
        <div class="tab-bar">
            <button class="tab-btn" :class="{ active: activeTab === 'basic' }" @click="switchTab('basic')">
                <span class="tab-icon">🧮</span><span class="tab-label">基础</span>
            </button>
            <button class="tab-btn" :class="{ active: activeTab === 'equation' }" @click="switchTab('equation')">
                <span class="tab-icon">📐</span><span class="tab-label">方程</span>
            </button>
            <button class="tab-btn" :class="{ active: activeTab === 'stats' }" @click="switchTab('stats')">
                <span class="tab-icon">📊</span><span class="tab-label">统计</span>
            </button>
            <button class="tab-btn" :class="{ active: activeTab === 'tools' }" @click="switchTab('tools')">
                <span class="tab-icon">🔧</span><span class="tab-label">工具</span>
            </button>
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
    flex-direction: column;
    justify-content: flex-start;
    align-items: center;
}

/* 滑动指示点（桌面端隐藏，移动端显示）*/
.swipe-hint {
    display: none;
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
    padding: 10px 10px 6px;
    box-shadow:
        0 8px 32px rgba(0, 0, 0, .35),
        0 2px 8px rgba(0, 0, 0, .2),
        inset 0 1px 0 rgba(255, 255, 255, .06);
    display: flex;
    flex-direction: column;
    overflow-y: auto;
    overflow-x: hidden;
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
    padding: 12px 16px 10px;
    margin-bottom: 8px;
    flex: 0 0 auto;
    display: flex;
    flex-direction: column;
    font-family: "Courier New", "SF Mono", "Fira Code", monospace;
    height: 150px;
    overflow: hidden;
}

.screen-status {
    display: flex;
    gap: 8px;
    font-size: 11px;
    color: #6a7074;
    margin-bottom: 3px;
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
    font-size: 14px;
    color: #6a7074;
    font-family: inherit;
    padding: 3px 0;
    text-align: right;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    min-height: 22px;
}

.screen-hidden {
    visibility: hidden;
}

.screen-input-field {
    position: absolute;
    inset: 0;
    width: 100%;
    background: none;
    border: none;
    outline: none;
    font-size: 20px;
    font-family: inherit;
    color: transparent;
    caret-color: #1a1c1d;
    padding: 0;
    line-height: 1.4;
    z-index: 2;
}

.screen-input-field::placeholder {
    color: transparent;
}

.input-wrapper {
    position: relative;
    min-height: 28px;
}

.input-display {
    display: block;
    font-size: 20px;
    font-family: inherit;
    color: #1a1c1d;
    line-height: 1.4;
    white-space: pre-wrap;
    word-break: break-all;
    min-height: 28px;
    pointer-events: none;
    user-select: none;
}

.input-placeholder {
    color: #7a8085;
}

.input-display sup {
    font-size: 0.65em;
    vertical-align: super;
    line-height: 1;
    position: relative;
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
    min-width: 0;
    overflow: hidden;
}

/* 修复 flex-end + overflow 导致左侧内容无法滚动的问题 */
.output-row::before {
    content: '';
    flex: 1 0 0;
    min-width: 0;
}

.output-value {
    font-size: 30px;
    font-weight: 800;
    color: #111;
    white-space: nowrap;
    flex-shrink: 0;
    line-height: 1.4;
}

.output-value.dim {
    font-size: 30px;
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
    flex-wrap: nowrap;
    align-items: center;
    gap: 4px 10px;
    font-size: 11px;
    color: #5a6064;
    margin-top: 6px;
    letter-spacing: .3px;
    padding-top: 4px;
    border-top: 1px solid #c0c4c8;
    min-height: 22px;
    overflow: hidden;
}

/* ---- 功能切换按钮行 ---- */
.mode-toggle-row {
    display: grid;
    grid-template-columns: repeat(3, 1fr);
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

.mode-standard:hover {
    filter: brightness(1.08);
}

.mode-standard.active {
    background: linear-gradient(180deg, #7aadff 0%, #5b8def 40%, #4a7de0 100%);
    box-shadow: 0 1px 0 #6b9df0, 0 3px 8px rgba(74, 125, 224, .5), inset 0 1px 2px rgba(255, 255, 255, .2);
    transform: translateY(2px);
}

/* 求解 - 绿色 */
.mode-solve {
    background: linear-gradient(180deg, #4caf8e 0%, #3d9e7a 40%, #2e8b68 100%);
    color: #fff;
    box-shadow: 0 3px 0 #5dbf9f, 0 4px 6px rgba(0, 0, 0, .12);
    border: 1px solid #258060;
}

.mode-solve:hover {
    filter: brightness(1.08);
}

.mode-solve.active {
    background: linear-gradient(180deg, #6dd4aa 0%, #4caf8e 40%, #3d9e7a 100%);
    box-shadow: 0 1px 0 #5dbf9f, 0 3px 8px rgba(61, 158, 122, .5), inset 0 1px 2px rgba(255, 255, 255, .2);
    transform: translateY(2px);
}

/* 工具 - 琥珀色 */
.mode-tools {
    background: linear-gradient(180deg, #f0a050 0%, #e09040 40%, #d08030 100%);
    color: #fff;
    box-shadow: 0 3px 0 #f5b565, 0 4px 6px rgba(0, 0, 0, .12);
    border: 1px solid #c07520;
}

.mode-tools:hover {
    filter: brightness(1.08);
}

.mode-tools.active {
    background: linear-gradient(180deg, #f5b870 0%, #f0a050 40%, #e09040 100%);
    box-shadow: 0 1px 0 #f5b565, 0 3px 8px rgba(240, 160, 80, .5), inset 0 1px 2px rgba(255, 255, 255, .2);
    transform: translateY(2px);
}

/* 弧度/角度 - 橙色 */
.mode-deg {
    background: linear-gradient(180deg, #f0a050 0%, #e09040 40%, #d08030 100%);
    color: #fff;
    box-shadow: 0 3px 0 #f5b565, 0 4px 6px rgba(0, 0, 0, .12);
    border: 1px solid #c07520;
}

.mode-deg:hover {
    filter: brightness(1.08);
}

.mode-deg.active {
    background: linear-gradient(180deg, #f5b870 0%, #f0a050 40%, #e09040 100%);
    box-shadow: 0 1px 0 #f5b565, 0 3px 8px rgba(240, 160, 80, .5), inset 0 1px 2px rgba(255, 255, 255, .2);
    transform: translateY(2px);
}

/* 正/反函数 - 紫色 */
.mode-inv {
    background: linear-gradient(180deg, #8b6cc0 0%, #7a5bb0 40%, #6a4aa0 100%);
    color: #fff;
    box-shadow: 0 3px 0 #9c7dd0, 0 4px 6px rgba(0, 0, 0, .12);
    border: 1px solid #5a3890;
}

.mode-inv:hover {
    filter: brightness(1.08);
}

.mode-inv.active {
    background: linear-gradient(180deg, #a080d8 0%, #8b6cc0 40%, #7a5bb0 100%);
    box-shadow: 0 1px 0 #9c7dd0, 0 3px 8px rgba(138, 108, 192, .5), inset 0 1px 2px rgba(255, 255, 255, .2);
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
    font-size: 12px;
    line-height: 1;
    overflow: hidden;
    text-overflow: ellipsis;
    background: linear-gradient(180deg, #ececec 0%, #d8d8d8 40%, #c4c4c4 100%);
    border: 1px solid #9a9a9a;
    border-radius: 4px;
    color: #1a1a1a;
    cursor: pointer;
    transition: all .1s;
    font-family: KaTeX_Math, "Helvetica Neue", "Arial", "PingFang SC", sans-serif;
    font-style: normal;
    font-weight: 600;
    letter-spacing: 0;
    text-align: center;
    white-space: nowrap;
    box-sizing: border-box;
    box-shadow:
        0 3px 0 #a0a0a0,
        0 4px 8px rgba(0, 0, 0, .15),
        inset 0 1px 1px rgba(255, 255, 255, .6),
        inset 0 -1px 2px rgba(0, 0, 0, .1);
}

.hint-tag:hover {
    filter: brightness(1.08);
    border-color: #7a7a7a;
    z-index: 20;
}

.hint-tag:active {
    filter: brightness(.92);
    transform: translateY(2px);
    box-shadow:
        0 1px 0 #a0a0a0,
        0 2px 4px rgba(0, 0, 0, .12),
        inset 0 1px 1px rgba(255, 255, 255, .4);
}

/* 2nd / Rad 激活红色态 */
.hint-active {
    background: linear-gradient(180deg, #e05555 0%, #c94040 40%, #b03030 100%) !important;
    border-color: #902020 !important;
    color: #fff !important;
    box-shadow:
        0 1px 0 #d05050,
        0 2px 4px rgba(0, 0, 0, .15),
        inset 0 1px 1px rgba(255, 255, 255, .2),
        inset 0 -1px 2px rgba(0, 0, 0, .1) !important;
    transform: translateY(2px);
}

/* ) 按钮：有未闭合括号时蓝色高亮提示 */
.hint-paren-open {
    background: linear-gradient(180deg, #5b8def 0%, #4a7de0 40%, #3a6ad0 100%) !important;
    border-color: #3570c0 !important;
    color: #fff !important;
}

/* 空占位：保持网格高度一致 */
.hint-empty {
    visibility: hidden;
    pointer-events: none;
}

/* 配速按钮：浅金金属质感 */
.hint-pace {
    background: linear-gradient(180deg, #f0e8d0 0%, #e0d4b0 40%, #d0c090 100%);
    border-color: #b0a060;
    color: #5a4a20;
    box-shadow:
        0 3px 0 #c0b080,
        0 4px 8px rgba(0, 0, 0, .12),
        inset 0 1px 1px rgba(255, 255, 255, .5),
        inset 0 -1px 2px rgba(0, 0, 0, .08);
}

.hint-pace:hover {
    filter: brightness(1.08);
    border-color: #908040;
    color: #3a2a10;
}

.hint-pace:active {
    filter: brightness(.92);
    transform: translateY(2px);
    box-shadow:
        0 1px 0 #c0b080,
        0 2px 4px rgba(0, 0, 0, .1);
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
    font-size: 12px;
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
    align-items: baseline;
    gap: 6px;
    padding: 4px 8px;
    border-radius: 4px;
    border: 1px solid transparent;
    font-size: 13px;
    font-family: -apple-system, "PingFang SC", "Microsoft YaHei", "Times New Roman", serif;
    color: #444;
    background: transparent;
    transition: background .1s;
    line-height: 1.6;
}

.solve-step-num {
    flex-shrink: 0;
    align-self: flex-start;
    margin-top: 1px;
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

.solve-step-hl .solve-step-num {
    background: #4a8a5a;
}

.solve-step-text {
    line-height: inherit;
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
    font-size: 12px;
}

.info-empty-icon {
    font-size: 48px;
    display: block;
    margin-bottom: 12px;
    opacity: .5;
}

.info-title {
    font-size: 12px;
    font-weight: 700;
    color: #8b9094;
    margin-bottom: 12px;
    padding-bottom: 8px;
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
    padding: 10px 5px;
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
    font-size: 11px;
    color: #8a9094;
    margin-bottom: 2px;
    letter-spacing: .5px;
}

.info-val {
    font-size: 14px;
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
    padding: 8px;
    border: 1px solid #c0c4c8;
    border-radius: 5px;
    background: transparent;
    color: #8a9094;
    font-size: 11px;
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
    font-size: 12px;
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
        position: fixed;
        bottom: calc(env(safe-area-inset-bottom, 0px) + 6px);
        left: 50%;
        transform: translateX(-50%);
        z-index: 200;
        padding: 6px 12px;
        background: rgba(45, 52, 54, .85);
        border-radius: 12px;
        backdrop-filter: blur(4px);
    }

    .swipe-dot {
        width: 6px;
        height: 6px;
        border-radius: 50%;
        background: #6a7074;
        transition: all .25s;
        cursor: pointer;
    }

    .swipe-dot.active {
        background: #d5d8dc;
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
    padding-bottom: 2px;
}

.calc-grid {
    display: grid;
    grid-template-columns: repeat(4, 1fr);
    row-gap: 8px;
    column-gap: 8px;
    margin-bottom: 0;
}

.calc-bottom-area {
    flex-shrink: 0;
    margin-top: 8px;
}

.calc-action-row {
    display: grid;
    grid-template-columns: 1fr;
    gap: 8px;
}

.calc-action-row.has-detail {
    grid-template-columns: 1fr 1fr;
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
    font-size: 1rem;
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
    font-size: 1.05rem;
    font-weight: 700;
    font-family: "Helvetica Neue", "Arial", sans-serif;
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
    background: linear-gradient(180deg, #ffb84d 0%, #ff9a2e 25%, #f6851b 50%, #e07510 100%);
    color: #fff;
    font-size: 1rem;
    font-weight: 600;
    border-radius: 5px;
    padding: 10px 4px;
    box-shadow:
        0 3px 0 #ffcc66,
        0 5px 8px rgba(0, 0, 0, .2),
        inset 0 1px 2px rgba(255, 255, 255, .25),
        inset 0 -1px 3px rgba(0, 0, 0, .05);
}

.calc-btn.calc-del:active {
    box-shadow:
        0 1px 0 #ffcc66,
        0 2px 4px rgba(0, 0, 0, .12);
}

.calc-btn.calc-space {
    width: 100%;
    border-radius: 5px;
    background: linear-gradient(180deg, #6da0cc 0%, #5b8cb8 40%, #4a78a0 100%);
    color: #e8f0f8;
    font-size: .9rem;
    font-weight: 600;
    padding: 12px 4px;
    letter-spacing: 2px;
    box-shadow:
        0 3px 0 #7db0d8,
        0 5px 8px rgba(0, 0, 0, .15),
        inset 0 1px 2px rgba(255, 255, 255, .2),
        inset 0 -1px 3px rgba(0, 0, 0, .08);
}

.calc-btn.calc-space:active {
    box-shadow:
        0 1px 0 #7db0d8,
        0 2px 4px rgba(0, 0, 0, .1);
}

/* 求解模式：绿色求解按钮 */
.calc-btn.calc-solve-btn {
    width: 100%;
    background: linear-gradient(180deg, #4caf8e 0%, #3d9e7a 45%, #2e8b68 100%);
    color: #fff;
    font-size: .9rem;
    font-weight: 700;
    border-radius: 5px;
    padding: 12px 4px;
    letter-spacing: 2px;
    box-shadow:
        0 3px 0 #5dbf9f,
        0 6px 10px rgba(0, 0, 0, .25),
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
    background: linear-gradient(180deg, #ffb84d 0%, #ff9a2e 25%, #f6851b 50%, #e07510 100%);
    color: #fff;
    font-size: 1rem;
    font-weight: 700;
    border-radius: 5px;
    padding: 10px 4px;
    box-shadow:
        0 3px 0 #ffcc66,
        0 5px 8px rgba(0, 0, 0, .2),
        inset 0 1px 2px rgba(255, 255, 255, .25),
        inset 0 -1px 3px rgba(0, 0, 0, .05);
}

.calc-btn.calc-clear:active {
    box-shadow:
        0 1px 0 #ffcc66,
        0 2px 4px rgba(0, 0, 0, .12);
}

.calc-btn.calc-sign {
    background: linear-gradient(180deg, #e5e5df 0%, #d5d5cf 40%, #c5c5bd 100%);
    color: #1a1a1a;
    font-size: 1rem;
    font-weight: 600;
    border-radius: 5px;
    padding: 10px 4px;
    box-shadow:
        0 3px 0 #a5a59b,
        0 5px 8px rgba(0, 0, 0, .1),
        inset 0 1px 2px rgba(255, 255, 255, .4),
        inset 0 -1px 3px rgba(0, 0, 0, .05);
}

.calc-btn.calc-sign:active {
    box-shadow:
        0 1px 0 #a5a59b,
        0 2px 4px rgba(0, 0, 0, .08);
}

.calc-btn.calc-equals {
    background: linear-gradient(180deg, #ffb84d 0%, #ff9a2e 25%, #f6851b 50%, #e07510 100%);
    color: #fff;
    font-size: 1.1rem;
    font-weight: 700;
    border-radius: 5px;
    padding: 10px 4px;
    box-shadow:
        0 3px 0 #ffcc66,
        0 6px 10px rgba(0, 0, 0, .25),
        inset 0 1px 2px rgba(255, 255, 255, .3),
        inset 0 -1px 3px rgba(0, 0, 0, .08);
}

.calc-btn.calc-equals:active {
    box-shadow:
        0 1px 0 #ffcc66,
        0 2px 4px rgba(0, 0, 0, .2),
        inset 0 1px 2px rgba(255, 255, 255, .2);
}

.calc-btn.calc-pct {
    background: linear-gradient(180deg, #ffb84d 0%, #ff9a2e 25%, #f6851b 50%, #e07510 100%);
    color: #fff;
    font-size: 1rem;
    font-weight: 600;
    border-radius: 5px;
    padding: 10px 4px;
    box-shadow:
        0 3px 0 #ffcc66,
        0 5px 8px rgba(0, 0, 0, .2),
        inset 0 1px 2px rgba(255, 255, 255, .25),
        inset 0 -1px 3px rgba(0, 0, 0, .05);
}

.calc-btn.calc-pct:active {
    box-shadow:
        0 1px 0 #ffcc66,
        0 2px 4px rgba(0, 0, 0, .12);
}

.calc-btn.calc-detail {
    background: linear-gradient(180deg, #6a7582 0%, #5a6570 40%, #4a5560 100%);
    color: #fff;
    font-size: .9rem;
    font-weight: 700;
    border-radius: 5px;
    padding: 12px 4px;
    box-shadow:
        0 3px 0 #7a8592,
        0 5px 8px rgba(0, 0, 0, .2),
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

/* ===== 蓝色运算符列高亮 (P0) ===== */
.calc-btn.calc-op {
    background: linear-gradient(180deg, #5b8def 0%, #4a7de0 40%, #3a6ad0 100%) !important;
    color: #fff !important;
    font-size: 1.2rem !important;
    font-weight: 600;
    font-family: "Helvetica Neue", "Arial", sans-serif !important;
    line-height: 1 !important;
    padding: 8px 4px !important;
    box-shadow:
        0 4px 0 #6b9df0,
        0 6px 10px rgba(74, 125, 224, .25),
        inset 0 1px 2px rgba(255, 255, 255, .2),
        inset 0 -1px 3px rgba(0, 0, 0, .1) !important;
}

.calc-btn.calc-op:active {
    box-shadow:
        0 1px 0 #6b9df0,
        0 2px 4px rgba(74, 125, 224, .15) !important;
}

/* ===== 底部Tab导航 (P1) ===== */
.tab-bar {
    display: flex;
    justify-content: center;
    gap: 2px;
    width: 100%;
    max-width: 420px;
    margin: 0 auto;
    padding: 6px 6px calc(env(safe-area-inset-bottom, 0px) + 4px);
    background: linear-gradient(180deg, transparent, #2d3436 20%);
}

.tab-btn {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 2px;
    flex: 1;
    padding: 6px 2px;
    border: none;
    background: transparent;
    color: #6a7074;
    font-size: 10px;
    font-weight: 600;
    cursor: pointer;
    border-radius: 8px;
    transition: all .15s;
    -webkit-tap-highlight-color: transparent;
    font-family: "Helvetica Neue", "PingFang SC", sans-serif;
}

.tab-btn:hover {
    color: #a0a8ac;
}

.tab-btn.active {
    color: #5b8def;
    background: rgba(91, 141, 239, .12);
}

.tab-icon {
    font-size: 18px;
    line-height: 1;
}

.tab-label {
    font-size: 9px;
    letter-spacing: .5px;
}

/* ===== 等级评定注释 (P0) ===== */
.grade-note {
    font-size: 10px;
    color: #6a7074;
    margin-bottom: 8px;
    padding: 4px 8px;
    background: #f0f2f4;
    border-radius: 4px;
    line-height: 1.5;
}

/* ===== 统计卡片分组 (P1) ===== */
.stat-group {
    margin-bottom: 10px;
}

.stat-group-label {
    font-size: 9px;
    font-weight: 700;
    color: #8b9094;
    margin-bottom: 4px;
    letter-spacing: 1.5px;
    text-transform: uppercase;
}

.info-grid-2col {
    grid-template-columns: repeat(2, 1fr) !important;
}

.info-grid-4col {
    grid-template-columns: repeat(4, 1fr) !important;
}

/* ===== 历史记录筛选标签 (P1) ===== */
.history-filters {
    display: flex;
    gap: 3px;
    margin-bottom: 6px;
}

.history-filter-btn {
    padding: 2px 8px;
    font-size: 9px;
    font-weight: 600;
    border: 1px solid #c0c4c8;
    border-radius: 3px;
    background: transparent;
    color: #6a7074;
    cursor: pointer;
    transition: all .15s;
    font-family: "Helvetica Neue", "PingFang SC", sans-serif;
}

.history-filter-btn:hover {
    background: #e0e2e4;
}

.history-filter-btn.active {
    background: #5b8def;
    color: #fff;
    border-color: #5b8def;
}

.history-clear-btn {
    margin-left: auto;
    padding: 2px 6px;
    font-size: 11px;
    border: 1px solid transparent;
    border-radius: 3px;
    background: transparent;
    cursor: pointer;
    transition: all .15s;
}

.history-clear-btn:hover {
    background: #f0d0d4;
    border-color: #d0a0a4;
}

/* ===== 笛卡尔坐标系图表 ===== */
.graph-section {
    margin-top: 8px;
    border-top: 1px solid #c0c4c8;
    padding-top: 6px;
}

.graph-toggle {
    font-size: 10px;
    font-weight: 700;
    color: #5b8def;
    cursor: pointer;
    user-select: none;
    padding: 4px 0;
}

.graph-toggle:hover {
    color: #4a7de0;
}

.cartesian-graph {
    width: 100%;
    height: auto;
    margin-top: 4px;
    background: #d5d8dc;
    border-radius: 4px;
    border: 1px solid #d0d4d8;
}
</style>
