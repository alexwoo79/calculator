<script setup lang="ts">
import { ref, computed, onMounted, onUnmounted, nextTick, watch } from "vue";
import { solveEquation as solveEq } from "../utils/solver";
import { evaluateSingle, formatNum, splitTokens } from "../utils/evaluate";
import type { HistoryItem } from "../types";

// —— 内部类型 ——
interface TooltipState { show: boolean; text: string; x: number; y: number }
interface StatsResult { count: number; sum: number; max: number; min: number; avg: number; median: number; stddev: number; range: number }
interface RankedItem { idx: number; raw: number; rank: number; pct: number }
interface GradedItem extends RankedItem { grade: string }

const inputText = ref("");
const numbers = ref<number[]>([]);
const errorMsg = ref("");
const history = ref<HistoryItem[]>([]);
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

// ===== 历史记录滚动 =====
const historyIdx = ref(-1);   // -1 = 不在浏览中，0=最新，1=次新...
const savedInput = ref("");   // 进入历史浏览前的输入暂存

// ===== 功能模式 =====
const calcMode = ref<'standard' | 'solve'>('standard');
const useDegrees = ref(false);
const useInverse = ref(false);

// ===== LCD 动态字体大小 =====
const outputRow = ref<HTMLElement | null>(null);
const outputValueRef = ref<HTMLElement | null>(null);
const outputFontSize = ref(20);
const MIN_FONT_SIZE = 10;
const MAX_FONT_SIZE = 20;

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
    'Escape': 'AC',
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

    if (mapped === 'AC') {
        e.preventDefault();
        activeKey.value = mapped;
        playClick();
        calcClear();
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
    inputText.value += mapped === '÷' ? '/' : mapped === '×' ? '*' : mapped === '−' ? '-' : mapped;
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

// 计算器按键布局
const calcKeys: string[][] = [
    ['7', '8', '9', '÷'],
    ['4', '5', '6', '×'],
    ['1', '2', '3', '−'],
    ['0', '.', '⌫', '+'],
    ['(', ')', '^', '%'],
];
const calcFuncKeys: string[] = [];

function calcKeyTap(key: string): void {
    playClick();
    if (key === '⌫') {
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

function calcFuncTap(_fn: string): void {}

function calcClear(): void {
    playClick();
    inputText.value = '';
    errorMsg.value = '';
    displayResult.value = null;
    lastInput.value = '';
    lastResultValue.value = null;
    numbers.value = [];
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
    "nCr(n,r)": "组合数 C(n,r)", "nPr(n,r)": "排列数 P(n,r)", "x!": "阶乘", "x%": "百分比 ÷100",
    "hex2dec(x)": "十六进制→十进制", "bin2dec(x)": "二进制→十进制",
    "pi": "圆周率 π≈3.1416", "e": "自然常数 e≈2.7183",
    "1/x": "倒数", "x^2": "平方", "x^3": "立方",
    "km": "千米 (=1) · 距离单位", "Hour": "小时 (=1) · 时间单位",
    "Min": "分钟 (=1/60h) · 时间单位", "Second": "秒 (=1/3600h) · 简写 sec",
};

// ===== 动态预设函数（根据模式切换）=====
const standardHintsRad: string[] = [
    "sin(x)", "cos(x)", "tan(x)", "sqrt(x)", "cbrt(x)",
    "ln(x)", "lg(x)", "pow(x,y)", "abs(x)", "sign(x)",
    "floor(x)", "ceil(x)", "round(x)", "mod(x,y)",
    "sinh(x)", "cosh(x)", "tanh(x)", "hypot(x,y)",
    "deg(x)", "rad(x)", "nCr(n,r)", "nPr(n,r)", "x!",
    "x%", "hex2dec(x)", "bin2dec(x)", "pi", "e",
    "1/x", "x^2", "x^3", "km", "Hour", "Min", "Second",
];
const standardHintsDeg: string[] = [
    "sind(x)", "cosd(x)", "tand(x)", "sqrt(x)", "cbrt(x)",
    "ln(x)", "lg(x)", "pow(x,y)", "abs(x)", "sign(x)",
    "floor(x)", "ceil(x)", "round(x)", "mod(x,y)",
    "sinh(x)", "cosh(x)", "tanh(x)", "hypot(x,y)",
    "deg(x)", "rad(x)", "nCr(n,r)", "nPr(n,r)", "x!",
    "x%", "hex2dec(x)", "bin2dec(x)", "pi", "e",
    "1/x", "x^2", "x^3", "km", "Hour", "Min", "Second",
];
const standardHintsRadInv: string[] = [
    "asin(x)", "acos(x)", "atan(x)", "sqrt(x)", "cbrt(x)",
    "ln(x)", "lg(x)", "pow(x,y)", "abs(x)", "sign(x)",
    "floor(x)", "ceil(x)", "round(x)", "mod(x,y)",
    "sinh(x)", "cosh(x)", "tanh(x)", "hypot(x,y)",
    "deg(x)", "rad(x)", "nCr(n,r)", "nPr(n,r)", "x!",
    "x%", "hex2dec(x)", "bin2dec(x)", "pi", "e",
    "1/x", "x^2", "x^3", "km", "Hour", "Min", "Second",
];
const standardHintsDegInv: string[] = [
    "asin(x)", "acos(x)", "atan(x)", "sqrt(x)", "cbrt(x)",
    "ln(x)", "lg(x)", "pow(x,y)", "abs(x)", "sign(x)",
    "floor(x)", "ceil(x)", "round(x)", "mod(x,y)",
    "sinh(x)", "cosh(x)", "tanh(x)", "hypot(x,y)",
    "deg(x)", "rad(x)", "nCr(n,r)", "nPr(n,r)", "x!",
    "x%", "hex2dec(x)", "bin2dec(x)", "pi", "e",
    "km", "Hour", "Min", "Second",
];

const solveHints: string[] = [
    "ax^2+bx+c=0", "ax+b=0", "x^2+px+q=0", "ax^2+bx=0",
    "ax^3+bx^2+cx+d=0", "a/x+b=c", "sqrt(ax+b)=c",
    "a^x=b", "ln(x)=a", "abs(x)=a",
    "sin(x)=a", "cos(x)=a", "tan(x)=a",
];

const HINT_ROW_COUNT = 6;

const displayHints = computed(() => {
    const cols = calcMode.value === 'solve' ? 4 : 5;
    const total = HINT_ROW_COUNT * cols;
    let hints: string[];
    if (calcMode.value === 'solve') hints = solveHints;
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

onMounted(() => {
    window.addEventListener('resize', adjustFontSize);
});
onUnmounted(() => {
    window.removeEventListener('resize', adjustFontSize);
});

// ===== 方程求解（增强版：支持一次/二次/三次，含解题步骤）=====
const solveSteps = ref<any[]>([]);
const solveResult = ref<any>(null);

function clearResults(): void {
    numbers.value = [];
    errorMsg.value = "";
    displayResult.value = null;
    lastResultValue.value = null;
}

function fillFromHistory(item: HistoryItem): void {
    inputText.value = item.nums ? item.nums.map(formatNum).join(" ") : item.input;
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
    const trimmed = inputText.value.trim();
    const isNumber = trimmed !== "" && !isNaN(Number(trimmed)) && isFinite(Number(trimmed));

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

function handleKeyboardSubmit(): void {
    errorMsg.value = "";
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
            inputText.value = "";
            return;
        } catch (err: any) {
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

    const tokens = splitTokens(expr);
    const nums: number[] = [];
    for (const token of tokens) {
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
        if (tokens.length > 1 || nums.length > 1) {
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
                        <div class="output-row" ref="outputRow">
                            <span v-show="displayResult" ref="outputValueRef" class="output-value" :style="{ fontSize: outputFontSize + 'px' }">{{ displayResult }}<span v-if="resultUnit"
                                    class="output-unit" :style="{ fontSize: Math.max(outputFontSize * 0.7, 9) + 'px' }"> {{ resultUnit }}</span></span>
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
    font-weight: 800;
    color: #111;
    white-space: nowrap;
    flex-shrink: 0;
    line-height: 1.2;
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
