<script setup>
import { ref, computed } from "vue";

// 模式: "menu" | "keyboard" | "paste"
const mode = ref("menu");
const inputText = ref("");
const numbers = ref([]);
const errorMsg = ref("");
const history = ref([]);
const copiedIdx = ref(-1);
const darkMode = ref(false);
const quickPasteText = ref("");
const aBound = ref(75);
const bBound = ref(50);
const cBound = ref(25);
const showGrade = ref(false);
const gradeSortKey = ref("rank");   // 默认按排名升序
const gradeSortAsc = ref(true);
const showTouchPad = ref(true);
const showCalcPad = ref(true); // 显示计算器按键面板

// 计算器按键处理
const calcKeys = [
    // 数字行
    ['7', '8', '9', '÷'],
    ['4', '5', '6', '×'],
    ['1', '2', '3', '−'],
    ['0', '.', '⌫', '+'],
    ['(', ')', '^', '%'],
];
const calcFuncKeys = ['sin(', 'cos(', 'tan(', 'sqrt(', 'ln(', 'pi', 'abs(', 'pow('];

function calcKeyTap(key) {
    if (key === '⌫') {
        inputText.value = inputText.value.slice(0, -1);
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

function calcFuncTap(fn) {
    const trimmed = inputText.value.trim();
    const isNumber = trimmed !== '' && !isNaN(Number(trimmed)) && isFinite(Number(trimmed));
    if (fn === 'sin(' || fn === 'cos(' || fn === 'tan(' || fn === 'sqrt(' || fn === 'ln(' || fn === 'abs(') {
        if (isNumber) {
            inputText.value = fn + trimmed + ')';
        } else {
            inputText.value = trimmed ? trimmed + ' ' + fn : fn;
        }
    } else if (fn === 'pow(') {
        inputText.value = trimmed ? trimmed + ' ' + fn : fn;
    } else if (fn === 'pi') {
        inputText.value = trimmed ? trimmed + ' pi' : 'pi';
    }
}

function calcClear() {
    inputText.value = '';
    errorMsg.value = '';
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
    "pi", "e", "tau", "0xff", "0b10", "0o7",
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
    "pi": "圆周率 π≈3.1416", "e": "自然常数 e≈2.7183", "tau": "τ=2π≈6.2832",
    "0xff": "十六进制字面量", "0b10": "二进制字面量", "0o7": "八进制字面量",
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

// 深色模式切换
function toggleDarkMode() {
    darkMode.value = !darkMode.value;
}

// 历史记录点击复用
function fillFromHistory(item) {
    mode.value = "keyboard";
    inputText.value = item.nums ? item.nums.map(formatNum).join(" ") : item.input;
    errorMsg.value = "";
}

// 快捷粘贴：逗号/空格/换行分隔的数字批量计算
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
    // 常量 tau = 2*pi
    prepared = prepared.replace(/\btau\b/g, "(2*Math.PI)");

    prepared = prepared.replace(/\^/g, "**");
    return prepared;
}

// 计算单个表达式
function evaluateSingle(expr) {
    const prepared = prepareExpression(expr);
    // 使用 Function 构造器进行求值
    const result = new Function("Math", "factorial", "ncr", "npr", `"use strict"; return (${prepared});`)(Math, factorial, ncr, npr);
    const num = Number(result);
    if (isNaN(num) || !isFinite(num)) {
        throw new Error(`表达式 "${expr}" 结果不是有效数字`);
    }
    return num;
}

// 点击预设函数按钮：如输入栏有有效数字，则将其作为参数嵌入表达式
function insertHint(hint) {
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
    if (!input) return;

    try {
        const nums = [];
        // 先尝试将整行作为一个表达式求值（如 "1 + 3"）
        try {
            nums.push(evaluateSingle(input));
        } catch {
            // 整行求值失败，按空格分割逐个求值（如 "1 2 3"）
            const tokens = input.split(/\s+/);
            for (const token of tokens) {
                if (!token) continue;
                nums.push(evaluateSingle(token));
            }
        }
        if (nums.length === 0) {
            errorMsg.value = "未解析到有效的数字";
            return;
        }
        numbers.value = nums;
        addHistory("键盘", inputText.value, nums);
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

function goBack() {
    mode.value = "menu";
    numbers.value = [];
    errorMsg.value = "";
}

function clearResults() {
    numbers.value = [];
    errorMsg.value = "";
}

function formatNum(n) {
    return Number.isInteger(n) ? n.toString() : n.toFixed(4);
}
</script>

<template>
    <div class="calculator" :class="{ dark: darkMode }">
        <!-- 标题 -->
        <header class="header">
            <div class="logo">🧮</div>
            <h1>Any Calculator</h1>
            <p class="subtitle">支持表达式计算 · 统计分析</p>
            <span class="author">by Alex</span>
            <button class="dark-toggle" @click="toggleDarkMode" :title="darkMode ? '切换亮色' : '切换深色'">
                {{ darkMode ? '☀️' : '🌙' }}
            </button>
        </header>

        <!-- 主菜单 -->
        <div v-if="mode === 'menu'" class="menu">
            <button class="menu-btn keyboard-btn" @click="mode = 'keyboard'">
                <span class="btn-icon">⌨️</span>
                <span class="btn-title">键盘输入</span>
                <span class="btn-desc">手动输入数字或表达式</span>
            </button>
            <button class="menu-btn paste-btn" @click="mode = 'paste'">
                <span class="btn-icon">📋</span>
                <span class="btn-title">快捷粘贴</span>
                <span class="btn-desc">粘贴逗号/空格分隔的数字，快速统计</span>
            </button>
        </div>

        <!-- 键盘输入模式 -->
        <div v-if="mode === 'keyboard'" class="input-panel">
            <div class="panel-header">
                <button class="back-btn" @click="goBack">← 返回</button>
                <h2>⌨️ 键盘输入</h2>
            </div>
            <div class="hints">
                <span v-for="h in functionHints" :key="h" class="hint-tag" :data-tooltip="hintTooltips[h] || h"
                    @click="insertHint(h)">
                    {{ h }}
                </span>
            </div>
            <p class="hint-text">支持表达式，如: <code>0xff</code> <code>hex2dec(ff)</code> <code>bin2dec(1010)</code>
                <code>sind(90)</code> <code>5!</code> <code>100*15%</code>
            </p>
            <div class="input-row">
                <input v-model="inputText" class="text-input" placeholder="输入数字或表达式，用空格分隔..."
                    @keyup.enter="handleKeyboardSubmit" />
                <button class="action-btn primary" :disabled="!inputText.trim()" @click="handleKeyboardSubmit">
                    计算
                </button>
            </div>
            <p v-if="previewResult" class="preview-result">💡 {{ previewResult.value }}</p>
            <p v-if="errorMsg" class="error-msg">❌ {{ errorMsg }}</p>

            <!-- 计算器键盘切换 -->
            <div class="calc-pad-toggle">
                <button class="toggle-pad-btn" @click="showCalcPad = !showCalcPad">
                    {{ showCalcPad ? '🔽 收起键盘' : '🔼 展开触屏键盘' }}
                </button>
            </div>

            <!-- 计算器触屏按键面板 -->
            <div v-if="showCalcPad" class="calc-pad">
                <!-- 函数快捷键行 -->
                <div class="calc-func-row">
                    <button
                        v-for="fn in calcFuncKeys"
                        :key="fn"
                        class="calc-btn func"
                        @click="calcFuncTap(fn)"
                    >{{ fn }}</button>
                </div>
                <!-- 数字/运算符按键网格 -->
                <div class="calc-grid">
                    <template v-for="row in calcKeys" :key="row.join('')">
                        <button
                            v-for="key in row"
                            :key="key"
                            class="calc-btn"
                            :class="{
                                'calc-num': key >= '0' && key <= '9' || key === '.',
                                'calc-op': ['÷','×','−','+','^','%'].includes(key),
                                'calc-paren': key === '(' || key === ')',
                                'calc-del': key === '⌫',
                            }"
                            @click="calcKeyTap(key)"
                        >{{ key }}</button>
                    </template>
                </div>
                <!-- 底栏：清除 + 计算 -->
                <div class="calc-bottom-row">
                    <button class="calc-btn calc-clear" @click="calcClear">C</button>
                    <button class="calc-btn calc-equals" @click="handleKeyboardSubmit">=</button>
                </div>
            </div>
        </div>

        <!-- 快捷粘贴模式 -->
        <div v-if="mode === 'paste'" class="input-panel">
            <div class="panel-header">
                <button class="back-btn" @click="goBack">← 返回</button>
                <h2>📋 快捷粘贴</h2>
            </div>
            <p class="hint-text">粘贴逗号、空格或换行分隔的数字，自动批量计算统计</p>
            <div class="input-col">
                <textarea v-model="quickPasteText" class="paste-textarea"
                    placeholder="在此粘贴数据，例如：&#10;1, 2, 3, 4, 5&#10;或&#10;10 20 30" rows="5"></textarea>
                <button class="action-btn primary" :disabled="!quickPasteText.trim()" @click="handleQuickPaste">
                    统计
                </button>
            </div>
            <p v-if="errorMsg" class="error-msg">❌ {{ errorMsg }}</p>
        </div>

        <!-- 结果面板 -->
        <div v-if="stats" class="results">
            <div class="results-header">
                <h2>📊 计算结果</h2>
                <button class="action-btn small" @click="clearResults">清除</button>
            </div>
            <div class="stats-grid">
                <div class="stat-card" @click="copyToClipboard(stats.count, 0)">
                    <span class="stat-label">数字个数</span>
                    <span class="stat-value">{{ stats.count }}</span>
                    <span class="copy-hint" v-if="copiedIdx === 0">✅ 已复制</span>
                    <span class="copy-hint" v-else>📋</span>
                </div>
                <div class="stat-card" @click="copyToClipboard(formatNum(stats.sum), 1)">
                    <span class="stat-label">总和</span>
                    <span class="stat-value">{{ formatNum(stats.sum) }}</span>
                    <span class="copy-hint" v-if="copiedIdx === 1">✅ 已复制</span>
                    <span class="copy-hint" v-else>📋</span>
                </div>
                <div class="stat-card" @click="copyToClipboard(formatNum(stats.max), 2)">
                    <span class="stat-label">最大值</span>
                    <span class="stat-value highlight-max">{{ formatNum(stats.max) }}</span>
                    <span class="copy-hint" v-if="copiedIdx === 2">✅ 已复制</span>
                    <span class="copy-hint" v-else>📋</span>
                </div>
                <div class="stat-card" @click="copyToClipboard(formatNum(stats.min), 3)">
                    <span class="stat-label">最小值</span>
                    <span class="stat-value highlight-min">{{ formatNum(stats.min) }}</span>
                    <span class="copy-hint" v-if="copiedIdx === 3">✅ 已复制</span>
                    <span class="copy-hint" v-else>📋</span>
                </div>
                <div class="stat-card accent" @click="copyToClipboard(formatNum(stats.avg), 4)">
                    <span class="stat-label">平均值</span>
                    <span class="stat-value">{{ formatNum(stats.avg) }}</span>
                    <span class="copy-hint" v-if="copiedIdx === 4">✅ 已复制</span>
                    <span class="copy-hint" v-else>📋</span>
                </div>
                <div class="stat-card" @click="copyToClipboard(formatNum(stats.median), 5)">
                    <span class="stat-label">中位数</span>
                    <span class="stat-value">{{ formatNum(stats.median) }}</span>
                    <span class="copy-hint" v-if="copiedIdx === 5">✅ 已复制</span>
                    <span class="copy-hint" v-else>📋</span>
                </div>
                <div class="stat-card" @click="copyToClipboard(formatNum(stats.stddev), 6)">
                    <span class="stat-label">标准差</span>
                    <span class="stat-value">{{ formatNum(stats.stddev) }}</span>
                    <span class="copy-hint" v-if="copiedIdx === 6">✅ 已复制</span>
                    <span class="copy-hint" v-else>📋</span>
                </div>
                <div class="stat-card" @click="copyToClipboard(formatNum(stats.range), 7)">
                    <span class="stat-label">极差</span>
                    <span class="stat-value">{{ formatNum(stats.range) }}</span>
                    <span class="copy-hint" v-if="copiedIdx === 7">✅ 已复制</span>
                    <span class="copy-hint" v-else>📋</span>
                </div>
            </div>

            <!-- 等级评定开关 -->
            <label class="grade-toggle" v-if="rankedData.length > 0"
                data-tooltip="按分位百分比自动划分 A/B/C/D 四档，滑块可调阈值。适合考试成绩、绩效排名等场景">
                <input type="checkbox" v-model="showGrade" />
                <span>📊 等级评定</span>
            </label>
            <p v-if="showGrade && rankedData.length > 0" class="grade-hint">
                💡 按分位%自动分档，拖动滑块调整 A/B/C/D 阈值。适用于考试成绩、绩效评分等需要排名分等的场景
            </p>

            <!-- 等级评定 -->
            <div v-if="showGrade" class="grade-section">
                <div class="grade-header">
                    <span>📊 等级评定</span>
                    <div class="grade-header-right">
                        <button class="copy-table-btn" @click="copyGradeTable">
                            {{ gradeTableCopied ? '✅ 已复制' : '📋 复制表格' }}
                        </button>
                        <div class="grade-dist">
                            <span class="grade-badge a">A {{ gradeCounts.A }}</span>
                            <span class="grade-badge b">B {{ gradeCounts.B }}</span>
                            <span class="grade-badge c">C {{ gradeCounts.C }}</span>
                            <span class="grade-badge d">D {{ gradeCounts.D }}</span>
                        </div>
                    </div>
                </div>
                <div class="grade-sliders">
                    <label>A/B <span>{{ aBound }}%</span></label>
                    <input type="range" min="0" max="100" v-model.number="aBound" />
                    <label>B/C <span>{{ bBound }}%</span></label>
                    <input type="range" min="0" max="100" v-model.number="bBound" />
                    <label>C/D <span>{{ cBound }}%</span></label>
                    <input type="range" min="0" max="100" v-model.number="cBound" />
                </div>
                <div class="grade-table-wrap">
                    <table class="rank-table">
                        <thead>
                            <tr>
                                <th class="sortable" @click="toggleGradeSort('idx')">
                                    序号<span class="sort-arrow">{{ sortArrowFor('idx') }}</span>
                                </th>
                                <th class="sortable" @click="toggleGradeSort('raw')">
                                    数值<span class="sort-arrow">{{ sortArrowFor('raw') }}</span>
                                </th>
                                <th class="sortable" @click="toggleGradeSort('rank')">
                                    排名<span class="sort-arrow">{{ sortArrowFor('rank') }}</span>
                                </th>
                                <th class="sortable" @click="toggleGradeSort('pct')">
                                    分位%<span class="sort-arrow">{{ sortArrowFor('pct') }}</span>
                                </th>
                                <th class="sortable" @click="toggleGradeSort('grade')">
                                    等级<span class="sort-arrow">{{ sortArrowFor('grade') }}</span>
                                </th>
                            </tr>
                        </thead>
                        <tbody>
                            <tr v-for="r in sortedGradeData" :key="r.idx" :class="'grade-' + r.grade">
                                <td class="col-idx">{{ r.idx }}</td>
                                <td class="col-val">{{ formatNum(r.raw) }}</td>
                                <td class="col-rank">#{{ r.rank }}</td>
                                <td class="col-pct">{{ r.pct }}%</td>
                                <td class="col-grade">{{ r.grade }}</td>
                            </tr>
                        </tbody>
                    </table>
                </div>
            </div>

            <!-- 数字列表 -->
            <details class="number-list">
                <summary>查看所有数字 ({{ numbers.length }})</summary>
                <div class="number-tags">
                    <span v-for="(n, i) in numbers" :key="i" class="number-tag">{{ formatNum(n) }}</span>
                </div>
            </details>
        </div>

        <!-- 历史记录 -->
        <div v-if="history.length > 0" class="history">
            <h3>📝 历史记录</h3>
            <div class="history-list">
                <div v-for="item in history" :key="item.id" class="history-item" @click="fillFromHistory(item)">
                    <span class="history-source">{{ item.source === "键盘" ? "⌨️" : "📋"
                        }}</span>
                    <span class="history-input">{{ item.input }}</span>
                    <span class="history-result">
                        {{ item.count }}个 · 平均{{ formatNum(item.avg) }}
                    </span>
                    <span class="history-time">{{ item.time }}</span>
                </div>
            </div>
        </div>

    </div>
</template>

<style scoped>
.calculator {
    width: 100%;
    height: 100vh;
    background: #fff;
    padding: 24px 28px;
    overflow-y: auto;
}

/* Header */
.header {
    text-align: center;
    margin-bottom: 28px;
}

.logo {
    font-size: 32px;
    margin-bottom: 4px;
}

.header h1 {
    font-size: 20px;
    font-weight: 600;
    color: #1a1a2e;
}

.subtitle {
    color: #999;
    font-size: 13px;
    margin-top: 4px;
}

.author {
    display: inline-block;
    margin-top: 2px;
    font-size: 11px;
    color: #bbb;
}

/* Menu */
.menu {
    display: flex;
    flex-direction: column;
    gap: 12px;
}

.menu-btn {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 6px;
    padding: 22px 14px;
    border: 1.5px solid #eee;
    border-radius: 10px;
    background: #fafafa;
    cursor: pointer;
    transition: all .2s;
    color: #333;
}

.menu-btn:hover {
    border-color: #6366f1;
    background: #f5f3ff;
}

.btn-icon {
    font-size: 28px;
}

.btn-title {
    font-size: 14px;
    font-weight: 600;
}

.btn-desc {
    font-size: 11px;
    color: #999;
}

/* Input Panel */
.input-panel {
    animation: fadeIn .25s ease;
}

.panel-header {
    display: flex;
    align-items: center;
    gap: 10px;
    margin-bottom: 16px;
}

.panel-header h2 {
    font-size: 17px;
    font-weight: 600;
    color: #1a1a2e;
}

.back-btn {
    background: none;
    border: 1px solid #ddd;
    color: #666;
    padding: 4px 12px;
    border-radius: 6px;
    cursor: pointer;
    font-size: 12px;
    transition: all .15s;
}

.back-btn:hover {
    background: #f5f5f5;
    color: #333;
}

.hints {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(84px, 1fr));
    gap: 5px;
    margin-bottom: 10px;
}

.hint-tag {
    position: relative;
    display: inline-block;
    padding: 3px 6px;
    font-size: 11px;
    background: #f5f3ff;
    border: 1px solid #e8e5ff;
    border-radius: 4px;
    color: #6366f1;
    cursor: pointer;
    transition: all .15s;
    font-family: "SF Mono", "Fira Code", monospace;
    text-align: center;
    white-space: nowrap;
}

.hint-tag:hover {
    background: #ede9fe;
    border-color: #6366f1;
    z-index: 10;
}

/* 自定义 tooltip */
.hint-tag::after {
    content: attr(data-tooltip);
    position: absolute;
    bottom: calc(100% + 6px);
    left: 50%;
    transform: translateX(-50%);
    padding: 3px 8px;
    background: #1a1a2e;
    color: #fff;
    font-size: 11px;
    font-family: -apple-system, "PingFang SC", "Microsoft YaHei", sans-serif;
    white-space: nowrap;
    border-radius: 4px;
    pointer-events: none;
    opacity: 0;
    transition: opacity .15s;
}

.hint-tag::before {
    content: "";
    position: absolute;
    bottom: calc(100% + 1px);
    left: 50%;
    transform: translateX(-50%);
    border: 5px solid transparent;
    border-top-color: #1a1a2e;
    pointer-events: none;
    opacity: 0;
    transition: opacity .15s;
}

.hint-tag:hover::after,
.hint-tag:hover::before {
    opacity: 1;
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

/* ==================== 深色模式 ==================== */
.dark.calculator {
    background: #1a1a2e;
}

.dark .header h1,
.dark .panel-header h2,
.dark .results-header h2 {
    color: #e2e8f0;
}

.dark .subtitle {
    color: #7c7f93;
}

.dark .author {
    color: #5a5d73;
}

.dark .back-btn {
    color: #94a3b8;
    border-color: #334155;
}

.dark .back-btn:hover {
    background: #1e293b;
    color: #e2e8f0;
}

.dark .menu-btn {
    background: #1e293b;
    border-color: #334155;
    color: #cbd5e1;
}

.dark .menu-btn:hover {
    background: #312e81;
    border-color: #6366f1;
}

.dark .dark-toggle {
    border-color: #334155;
}

.dark .dark-toggle:hover {
    background: #1e293b;
}

.dark .hint-tag {
    background: #1e293b;
    border-color: #334155;
    color: #818cf8;
}

.dark .hint-tag:hover {
    background: #312e81;
    border-color: #818cf8;
}

.dark .hint-tag::after {
    background: #e2e8f0;
    color: #1a1a2e;
}

.dark .hint-tag::before {
    border-top-color: #e2e8f0;
}

.dark .hint-text {
    color: #7c7f93;
}

.dark .hint-text code {
    background: #1e293b;
    color: #818cf8;
}

.dark .text-input,
.dark .paste-textarea {
    background: #1e293b;
    border-color: #334155;
    color: #e2e8f0;
}

.dark .text-input:focus,
.dark .paste-textarea:focus {
    border-color: #6366f1;
}

.dark .text-input::placeholder,
.dark .paste-textarea::placeholder {
    color: #5a5d73;
}

.dark .file-drop-zone {
    background: #1e293b;
    border-color: #334155;
    color: #94a3b8;
}

.dark .file-drop-zone:hover {
    background: #312e81;
    border-color: #6366f1;
}

.dark .file-placeholder {
    color: #5a5d73;
}

.dark .file-selected {
    color: #818cf8;
}

.dark .stat-card {
    background: #1e293b;
}

.dark .stat-card:hover {
    background: #312e81;
}

.dark .stat-label {
    color: #7c7f93;
}

.dark .stat-value {
    color: #e2e8f0;
}

.dark .error-msg {
    background: #3b1016;
    border-color: #791f26;
    color: #fca5a5;
}

.dark .preview-result {
    background: #0d2818;
    border-color: #14532d;
    color: #86efac;
}

.dark .number-tag {
    background: #1e293b;
    color: #94a3b8;
}

.dark .history {
    border-color: #2d3748;
}

.dark .history h3 {
    color: #7c7f93;
}

.dark .history-item {
    background: #1e293b;
}

.dark .history-item:hover {
    background: #283548;
}

.dark .history-input {
    color: #94a3b8;
}

.dark .history-time {
    color: #5a5d73;
}

.dark .number-list summary {
    color: #7c7f93;
}

.dark .rank-table-wrap {
    border-color: #2d3748;
}

.dark .rank-table th {
    background: #1e293b;
    color: #7c7f93;
    border-color: #2d3748;
}

.dark .rank-table th.sortable:hover {
    color: #818cf8;
}

.dark .rank-table td {
    color: #94a3b8;
    border-color: #283548;
}

.dark .rank-table tbody tr:hover {
    background: #283548;
}

.dark .col-idx {
    color: #5a5d73;
}

.dark .col-rank {
    color: #818cf8;
}

.dark .col-pct {
    color: #86efac;
}

.dark .action-btn.small {
    background: #1e293b;
    color: #7c7f93;
}

.dark .action-btn.small:hover {
    background: #283548;
    color: #94a3b8;
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

/* ==================== 计算器触屏按键面板 ==================== */
.calc-pad-toggle {
    text-align: center;
    margin-top: 12px;
}

.toggle-pad-btn {
    background: none;
    border: 1px solid #e8e5ff;
    color: #6366f1;
    padding: 6px 16px;
    border-radius: 6px;
    font-size: 12px;
    cursor: pointer;
    transition: all .15s;
}

.toggle-pad-btn:hover {
    background: #f5f3ff;
    border-color: #6366f1;
}

.calc-pad {
    margin-top: 12px;
    padding: 14px;
    background: #fafafa;
    border: 1px solid #f0f0f0;
    border-radius: 12px;
    animation: fadeIn .2s ease;
    user-select: none;
    -webkit-user-select: none;
}

/* 函数快捷键行 */
.calc-func-row {
    display: flex;
    flex-wrap: wrap;
    gap: 6px;
    margin-bottom: 10px;
}

/* 数字/运算符网格 */
.calc-grid {
    display: grid;
    grid-template-columns: repeat(4, 1fr);
    gap: 8px;
    margin-bottom: 8px;
}

/* 底栏 */
.calc-bottom-row {
    display: grid;
    grid-template-columns: 1fr 2fr;
    gap: 8px;
}

/* 通用按键 */
.calc-btn {
    padding: 14px 4px;
    border: none;
    border-radius: 10px;
    font-size: 18px;
    font-weight: 600;
    font-family: "SF Mono", "Fira Code", "PingFang SC", monospace;
    cursor: pointer;
    transition: all .12s;
    text-align: center;
    outline: none;
    -webkit-tap-highlight-color: transparent;
    touch-action: manipulation;
}

.calc-btn:active {
    transform: scale(0.94);
}

/* 数字键 */
.calc-btn.calc-num {
    background: #fff;
    color: #1a1a2e;
    border: 1.5px solid #e5e7eb;
    font-size: 20px;
}

.calc-btn.calc-num:active {
    background: #eef2ff;
    border-color: #6366f1;
}

/* 运算符键 */
.calc-btn.calc-op {
    background: #f5f3ff;
    color: #6366f1;
    font-size: 20px;
}

.calc-btn.calc-op:active {
    background: #ddd6fe;
}

/* 括号键 */
.calc-btn.calc-paren {
    background: #f0f9ff;
    color: #0284c7;
    font-size: 18px;
}

.calc-btn.calc-paren:active {
    background: #e0f2fe;
}

/* 删除键 */
.calc-btn.calc-del {
    background: #fef2f2;
    color: #dc2626;
    font-size: 18px;
}

.calc-btn.calc-del:active {
    background: #fee2e2;
}

/* 函数快捷键 */
.calc-func-row .calc-btn.func {
    flex: 1;
    min-width: 52px;
    padding: 8px 4px;
    font-size: 13px;
    font-weight: 500;
    background: #f0fdf4;
    color: #16a34a;
    border: 1px solid #dcfce7;
    border-radius: 8px;
}

.calc-func-row .calc-btn.func:active {
    background: #dcfce7;
}

/* 清除键 */
.calc-btn.calc-clear {
    background: #fef2f2;
    color: #dc2626;
    font-size: 18px;
    font-weight: 700;
}

.calc-btn.calc-clear:active {
    background: #fee2e2;
}

/* 等号键 */
.calc-btn.calc-equals {
    background: #6366f1;
    color: #fff;
    font-size: 22px;
    font-weight: 700;
}

.calc-btn.calc-equals:active {
    background: #4f46e5;
}

/* ==================== 深色模式下的计算器面板 ==================== */
.dark .calc-pad-toggle .toggle-pad-btn {
    border-color: #334155;
    color: #818cf8;
}

.dark .toggle-pad-btn:hover {
    background: #1e293b;
    border-color: #6366f1;
}

.dark .calc-pad {
    background: #1e293b;
    border-color: #2d3748;
}

.dark .calc-btn.calc-num {
    background: #0f172a;
    border-color: #334155;
    color: #e2e8f0;
}

.dark .calc-btn.calc-num:active {
    background: #312e81;
    border-color: #6366f1;
}

.dark .calc-btn.calc-op {
    background: #312e81;
    color: #a5b4fc;
}

.dark .calc-btn.calc-op:active {
    background: #3730a3;
}

.dark .calc-btn.calc-paren {
    background: #1e3a5f;
    color: #7dd3fc;
}

.dark .calc-btn.calc-paren:active {
    background: #1e40af;
}

.dark .calc-btn.calc-del {
    background: #3b1016;
    color: #fca5a5;
}

.dark .calc-btn.calc-del:active {
    background: #581c1c;
}

.dark .calc-func-row .calc-btn.func {
    background: #14532d;
    color: #86efac;
    border-color: #166534;
}

.dark .calc-func-row .calc-btn.func:active {
    background: #166534;
}

.dark .calc-btn.calc-clear {
    background: #3b1016;
    color: #fca5a5;
}

.dark .calc-btn.calc-clear:active {
    background: #581c1c;
}

.dark .calc-btn.calc-equals {
    background: #6366f1;
    color: #fff;
}

.dark .calc-btn.calc-equals:active {
    background: #4f46e5;
}
</style>
