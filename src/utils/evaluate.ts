/**
 * 表达式求值模块
 * 将数学表达式字符串转换为可求值的 JavaScript 并计算结果
 */

// 单位常量
export const UNITS = {
    km: 1,
    Hour: 1,
    hour: 1,
    Min: 1 / 60,
    min: 1 / 60,
    Second: 1 / 3600,
    sec: 1 / 3600,
    second: 1 / 3600,
} as const;

export function factorial(n: number): number {
    if (n < 0) throw new Error("阶乘不支持负数");
    if (!Number.isInteger(n)) throw new Error("阶乘仅支持整数");
    if (n > 170) throw new Error("阶乘数值过大");
    let r = 1;
    for (let i = 2; i <= n; i++) r *= i;
    return r;
}

export function ncr(n: number, r: number): number {
    if (r < 0 || r > n) throw new Error("nCr 参数无效");
    return Math.round(factorial(n) / (factorial(r) * factorial(n - r)));
}

export function npr(n: number, r: number): number {
    if (r < 0 || r > n) throw new Error("nPr 参数无效");
    return Math.round(factorial(n) / factorial(n - r));
}

/** 格式化数字：整数直接显示，小数保留4位 */
export function formatNum(n: number): string {
    return Number.isInteger(n) ? n.toString() : n.toFixed(4);
}

/** 将数学表达式字符串转换为 JavaScript 可求值的形式 */
export function prepareExpression(expr: string): string {
    let prepared = expr.trim().toLowerCase();

    const unitVars = 'km|hour|min|second|sec|pi|e';
    const timeVars = 'hour|min|second|sec';

    // 隐式乘法处理
    prepared = prepared.replace(new RegExp(`(\\d)\\s+(${unitVars})\\b`, 'g'), '$1*$2');
    prepared = prepared.replace(new RegExp(`\\b(${timeVars})\\s+(\\d)`, 'g'), '$1 + $2');
    prepared = prepared.replace(new RegExp(`\\b(km)\\s+(\\d)`, 'g'), '$1*$2');
    prepared = prepared.replace(new RegExp(`\\b(${unitVars})\\s+(${unitVars})\\b`, 'g'), '$1*$2');
    prepared = prepared.replace(new RegExp(`(\\d)(${unitVars})\\b`, 'g'), '$1*$2');

    // 除法后时间表达式加括号
    prepared = prepared.replace(
        new RegExp(`/\\s*(\\d+(?:\\.\\d+)?\\s*\\*\\s*(?:${timeVars})\\b(?:\\s*\\+\\s*\\d+(?:\\.\\d+)?\\s*\\*\\s*(?:${timeVars})\\b)*)`, 'g'),
        (_, terms: string) => `/(${terms.trim()})`
    );

    // 百分号、阶乘
    prepared = prepared.replace(/(\d+\.?\d*)%/g, "($1/100)");
    prepared = prepared.replace(/(\d+\.?\d*)!/g, "factorial($1)");

    // 组合与排列
    prepared = prepared.replace(/\bncr\s*\((\d+)\s*,\s*(\d+)\)/g, "ncr($1,$2)");
    prepared = prepared.replace(/\bnpr\s*\((\d+)\s*,\s*(\d+)\)/g, "npr($1,$2)");

    // 第1轮：直接映射到 Math.*
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
    prepared = prepared.replace(/\bpow\b/g, "Math.pow");

    // 第2轮：基础函数
    prepared = prepared.replace(/\bsin\b/g, "Math.sin");
    prepared = prepared.replace(/\bcos\b/g, "Math.cos");
    prepared = prepared.replace(/\btan\b/g, "Math.tan");
    prepared = prepared.replace(/\bpi\b/g, "Math.PI");
    prepared = prepared.replace(/\babs\b/g, "Math.abs");
    prepared = prepared.replace(/\bsqrt\b/g, "Math.sqrt");
    prepared = prepared.replace(/\bln\b/g, "Math.log");
    prepared = prepared.replace(/\blg\b/g, "Math.log10");
    prepared = prepared.replace(/\be\b(?![a-zA-Z])/g, "Math.E");

    // 第3轮：派生函数
    prepared = prepared.replace(/\bsind\(([^)]+)\)/g, "Math.sin(($1)*Math.PI/180)");
    prepared = prepared.replace(/\bcosd\(([^)]+)\)/g, "Math.cos(($1)*Math.PI/180)");
    prepared = prepared.replace(/\btand\(([^)]+)\)/g, "Math.tan(($1)*Math.PI/180)");
    prepared = prepared.replace(/\brad\(([^)]+)\)/g, "(($1)*Math.PI/180)");
    prepared = prepared.replace(/\bdeg\(([^)]+)\)/g, "(($1)*180/Math.PI)");
    prepared = prepared.replace(/\bmod\(([^,]+),([^)]+)\)/g, "(($1%$2+$2)%$2)");
    prepared = prepared.replace(/\bhex2dec\(([a-f0-9]+)\)/g, 'parseInt("$1",16)');
    prepared = prepared.replace(/\bbin2dec\(([01]+)\)/g, 'parseInt("$1",2)');
    prepared = prepared.replace(/\^/g, "**");

    return prepared;
}

/** 计算单个表达式的值，失败返回 NaN */
export function evaluateSingle(expr: string): number {
    const prepared = prepareExpression(expr);
    try {
        const result = new Function(
            "Math", "factorial", "ncr", "npr",
            "km", "Hour", "Min", "Second",
            "hour", "min", "second", "sec",
            `"use strict"; return (${prepared});`
        )(
            Math, factorial, ncr, npr,
            1, 1, 1 / 60, 1 / 3600,
            1, 1 / 60, 1 / 3600, 1 / 3600
        );
        const num = Number(result);
        return (!isNaN(num) && isFinite(num)) ? num : NaN;
    } catch {
        return NaN;
    }
}
