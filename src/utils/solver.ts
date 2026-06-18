/**
 * 方程求解模块
 * 支持：一次/二次/三次多项式、根式、分式、指数、对数、绝对值、三角方程
 */

import type { SolveResult, SolveStep, PolyCoeffs } from "../types";
import { formatNum } from "./evaluate";

// —— 简单求值（无数学函数库）——
function safeEvalSimple(expr: string): number {
    const s = String(expr).trim().replace(/\^/g, '**');
    try {
        return new Function(`"use strict"; return (${s});`)();
    } catch {
        return NaN;
    }
}

// —— 系数格式化 ——
function formatCoeff(v: number): string {
    if (Math.abs(v - 1) < 1e-10) return '1';
    if (Math.abs(v + 1) < 1e-10) return '-1';
    return formatNum(v);
}

function formatCoeff2(v: number): string {
    if (Math.abs(v - 1) < 1e-10) return '+';
    if (Math.abs(v + 1) < 1e-10) return '-';
    if (v >= 0) return `+${formatNum(v)}`;
    return `-${formatNum(Math.abs(v))}`;
}

function subNum(n: number): string {
    const subs = ['₀', '₁', '₂', '₃', '₄', '₅'];
    return subs[n] || String(n);
}

// —— 多项式格式化 ——
export function fmtPoly(coeffs: number[], vars: string[] = ['x^3', 'x^2', 'x', '']): string {
    const terms: string[] = [];
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

// —— 多项式系数解析 ——
function parsePolynomial(expr: string): PolyCoeffs {
    let s = expr.replace(/\s/g, '').toLowerCase();
    s = s.replace(/\^/g, '^');
    s = s.replace(/(\d)(x)/g, '$1*x');
    s = s.replace(/(x)(\d)/g, '$1*$2');
    s = s.replace(/\)\(/g, ')*(');
    s = s.replace(/(\d)\(/g, '$1*(');
    s = s.replace(/\)(\d)/g, ')*$1');

    function evalAt(val: number): number {
        const substituted = s.replace(/x/g, `(${val})`).replace(/\^/g, '**');
        try { return new Function(`"use strict"; return (${substituted});`)(); }
        catch { return NaN; }
    }

    const f0 = evalAt(0);
    const f1 = evalAt(1);
    const fm1 = evalAt(-1);
    const f2 = evalAt(2);

    if ([f0, f1, fm1, f2].some(v => isNaN(v) || !isFinite(v))) {
        throw new Error("表达式无法解析，请检查格式");
    }

    const d = f0;
    const sum1 = f1 - d;
    const sumM1 = fm1 - d;
    const sum2 = f2 - d;

    const a2 = (sum1 + sumM1) / 2;
    const a3_plus_a1 = (sum1 - sumM1) / 2;
    const a3 = (sum2 - 4 * a2 - 2 * a3_plus_a1) / 6;
    const a1 = a3_plus_a1 - a3;

    return {
        a3, a2, a1, a0: d,
        coeffs: [d, a1, a2, a3],
    };
}

// —— 各类型求解器 ——
function solveLinear(b: number, c: number, steps: SolveStep[]): SolveResult {
    const eqText = fmtPoly([b, c], ['x', '']);
    steps.push({ text: `一次方程: ${eqText} = 0`, hl: true });
    const x = -c / b;
    steps.push({ text: `移项: ${formatCoeff2(b)}x = ${formatNum(-c)}`, hl: false });
    steps.push({ text: `x = ${formatNum(-c)} ÷ ${formatNum(b)} = ${formatNum(x)}`, hl: false });
    steps.push({ text: `✓ 解: x = ${formatNum(x)}`, hl: true });
    return { type: 'linear', degree: 1, solutions: [formatNum(x)], display: `x = ${formatNum(x)}`, b, c };
}

function solveQuadratic(a: number, b: number, c: number, steps: SolveStep[]): SolveResult {
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
        return { type: 'quadratic', a, b, c, delta: 0, degree: 2, solutions: [formatNum(x)], display };
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
        return { type: 'quadratic', a, b, c, delta, degree: 2, solutions: [formatNum(x1), formatNum(x2)], display };
    }
}

function solveCubic(a3: number, a2: number, a1: number, a0: number, steps: SolveStep[]): SolveResult {
    const eqText = fmtPoly([a3, a2, a1, a0], ['x^3', 'x^2', 'x', '']);
    steps.push({ text: `三次方程: ${eqText} = 0`, hl: true });

    const p = a2 / a3, q = a1 / a3, r = a0 / a3;
    const stdEq = fmtPoly([1, p, q, r], ['x^3', 'x^2', 'x', '']);
    steps.push({ text: `标准化 (除以${formatNum(a3)}): ${stdEq} = 0`, hl: false });

    const P = q - (p * p) / 3;
    const Q = r - (p * q) / 3 + (2 * p * p * p) / 27;
    steps.push({ text: `令 x = y - p/3, 消去二次项:`, hl: false });
    steps.push({ text: `P = q - p²/3 = ${formatNum(P)}`, hl: false });
    steps.push({ text: `Q = r - pq/3 + 2p³/27 = ${formatNum(Q)}`, hl: false });
    steps.push({ text: `化为: ${fmtPoly([1, 0, P, Q], ['y^3', 'y^2', 'y', ''])} = 0`, hl: true });

    const discriminant = (Q * Q) / 4 + (P * P * P) / 27;
    steps.push({ text: `判别式: Δ = Q²/4 + P³/27 = ${formatNum(discriminant)}`, hl: false });

    const solutions: string[] = [];
    const shift = p / 3;

    if (Math.abs(discriminant) < 1e-10) {
        steps.push({ text: 'Δ = 0，有三个实根（至少两个相等）', hl: false });
        const u = Math.cbrt(-Q / 2);
        const x1 = 2 * u - shift, x2 = -u - shift;
        solutions.push(formatNum(x1), formatNum(x2), formatNum(x2));
        steps.push({ text: `u = ∛(−Q/2) = ${formatNum(u)}`, hl: false });
        steps.push({ text: `✓ x₁ = 2u − p/3 = ${formatNum(x1)}`, hl: true });
        steps.push({ text: `✓ x₂ = x₃ = −u − p/3 = ${formatNum(x2)} (重根)`, hl: true });
    } else if (discriminant > 1e-10) {
        steps.push({ text: 'Δ > 0，有一个实根和两个共轭复根', hl: false });
        const sqrtD = Math.sqrt(discriminant);
        const u = Math.cbrt(-Q / 2 + sqrtD), v = Math.cbrt(-Q / 2 - sqrtD);
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
        steps.push({ text: 'Δ < 0，有三个不等实根（三角函数法）', hl: false });
        const phi = Math.acos((-Q / 2) / Math.sqrt(-(P * P * P) / 27));
        const rVal = 2 * Math.sqrt(-P / 3);
        steps.push({ text: `φ = arccos(−Q/2 / √(−P³/27)) = ${formatNum(phi)} rad`, hl: false });
        steps.push({ text: `r = 2√(−P/3) = ${formatNum(rVal)}`, hl: false });
        for (let k = 0; k < 3; k++) {
            const angle = (phi + 2 * Math.PI * k) / 3;
            const xk = rVal * Math.cos(angle) - shift;
            solutions.push(formatNum(xk));
            steps.push({ text: `✓ x${k + 1} = r·cos((φ+2π·${k})/3) − p/3 = ${formatNum(xk)}`, hl: true });
        }
    }

    const display = solutions.map((s, i) => `x${subNum(i + 1)} = ${s}`).join('\n');
    return { type: 'cubic', degree: 3, a3, a: a2, b: a1, c: a0, solutions, display };
}

// 非多项式求解器
function solveRadical(inner: string, right: string, steps: SolveStep[]): SolveResult {
    steps.push({ text: `根式方程: √(${inner}) = ${right}`, hl: true });
    const c = safeEvalSimple(right);
    if (isNaN(c) || c < 0) throw new Error("根式方程右边必须 ≥ 0");
    const c2 = c * c;
    steps.push({ text: `两边平方: ${inner} = ${right}² = ${formatNum(c2)}`, hl: false });
    const poly = parsePolynomial(`(${inner})-(${formatNum(c2)})`);
    const [d, b, a] = poly.coeffs;
    if (Math.abs(a) > 1e-10) {
        const x = -b / a;
        steps.push({ text: `x = ${formatNum(-b)} / ${formatNum(a)} = ${formatNum(x)}`, hl: false });
        steps.push({ text: `✓ x = ${formatNum(x)}`, hl: true });
        return { type: 'radical', degree: 1, solutions: [formatNum(x)], display: `x = ${formatNum(x)}` };
    }
    const x = -d / b;
    steps.push({ text: `x = ${formatNum(-d)} / ${formatNum(b)} = ${formatNum(x)}`, hl: false });
    steps.push({ text: `✓ x = ${formatNum(x)}`, hl: true });
    return { type: 'radical', degree: 1, solutions: [formatNum(x)], display: `x = ${formatNum(x)}` };
}

function solveRational(left: string, right: string, steps: SolveStep[]): SolveResult {
    steps.push({ text: `分式方程: ${left} = ${right}`, hl: true });
    const cVal = safeEvalSimple(right.replace(/\^/g, '**'));
    if (isNaN(cVal)) throw new Error("右边无法计算");
    const parts = left.split(/([+-])/);
    let a = 1, b = 0, sign = 1;
    for (const p of parts) {
        const pt = p.trim();
        if (pt === '+') sign = 1;
        else if (pt === '-') sign = -1;
        else if (pt.includes('/x')) {
            const num = pt.replace('/x', '').trim();
            a = sign * (num === '' || num === '+' ? 1 : num === '-' ? -1 : safeEvalSimple(num));
        } else if (pt && !pt.includes('/')) {
            b += sign * safeEvalSimple(pt);
        }
    }
    const denom = cVal - b;
    if (Math.abs(denom) < 1e-10) throw new Error("分母为零，无解");
    const x = a / denom;
    steps.push({ text: `x = ${formatNum(a)} / ${formatNum(denom)} = ${formatNum(x)}`, hl: false });
    steps.push({ text: `✓ x = ${formatNum(x)}`, hl: true });
    return { type: 'rational', degree: 1, solutions: [formatNum(x)], display: `x = ${formatNum(x)}` };
}

function solveExponential(left: string, right: string, steps: SolveStep[]): SolveResult {
    const a = parseFloat(left.replace('^x', ''));
    const b = parseFloat(right);
    steps.push({ text: `指数方程: ${a}^x = ${b}`, hl: true });
    steps.push({ text: `取自然对数: x·ln(${a}) = ln(${b})`, hl: false });
    const x = Math.log(b) / Math.log(a);
    steps.push({ text: `x = ln(${b}) / ln(${a}) = ${formatNum(x)}`, hl: false });
    steps.push({ text: `✓ x = ${formatNum(x)}`, hl: true });
    return { type: 'exponential', degree: 0, solutions: [formatNum(x)], display: `x = ${formatNum(x)}` };
}

function solveLogarithmic(right: string, steps: SolveStep[]): SolveResult {
    const a = safeEvalSimple(right);
    steps.push({ text: `对数方程: ln(x) = ${formatNum(a)}`, hl: true });
    const x = Math.exp(a);
    steps.push({ text: `x = e^${formatNum(a)} = ${formatNum(x)}`, hl: false });
    steps.push({ text: `✓ x = ${formatNum(x)}`, hl: true });
    return { type: 'logarithmic', degree: 0, solutions: [formatNum(x)], display: `x = ${formatNum(x)}` };
}

function solveAbsolute(inner: string, right: string, steps: SolveStep[]): SolveResult {
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

function solveTrig(func: string, inner: string, right: string, steps: SolveStep[], useDeg: boolean): SolveResult {
    const a = safeEvalSimple(right);
    steps.push({ text: `三角方程: ${func}(${inner}) = ${formatNum(a)}`, hl: true });
    if (Math.abs(a) > 1) throw new Error(`${func} 的值域为 [-1, 1]，${formatNum(a)} 超出范围`);

    const radVal = func === 'sin' ? Math.asin(a) : func === 'cos' ? Math.acos(a) : Math.atan(a);
    const degVal = radVal * 180 / Math.PI;

    if (func === 'sin') {
        if (useDeg) {
            steps.push({ text: `x₁ = arcsin(${formatNum(a)}) = ${formatNum(degVal)}°`, hl: false });
            const x2 = 180 - degVal;
            steps.push({ text: `x₂ = 180° − ${formatNum(degVal)}° = ${formatNum(x2)}°`, hl: false });
            steps.push({ text: `✓ x₁ = ${formatNum(degVal)}°  |  x₂ = ${formatNum(x2)}°`, hl: true });
            return { type: 'trig', degree: 0, solutions: [formatNum(degVal) + '°', formatNum(x2) + '°'], display: `x₁ = ${formatNum(degVal)}°  |  x₂ = ${formatNum(x2)}°` };
        }
        const x2 = Math.PI - radVal;
        steps.push({ text: `x₁ = arcsin(${formatNum(a)}) = ${formatNum(radVal)} rad`, hl: false });
        steps.push({ text: `✓ x₁ = ${formatNum(radVal)} rad  |  x₂ = ${formatNum(x2)} rad`, hl: true });
        return { type: 'trig', degree: 0, solutions: [formatNum(radVal) + ' rad', formatNum(x2) + ' rad'], display: `x₁ = ${formatNum(radVal)} rad  |  x₂ = ${formatNum(x2)} rad` };
    } else if (func === 'cos') {
        if (useDeg) {
            const x2 = -degVal;
            steps.push({ text: `x₁ = arccos(${formatNum(a)}) = ${formatNum(degVal)}°`, hl: false });
            steps.push({ text: `✓ x₁ = ${formatNum(degVal)}°  |  x₂ = ${formatNum(x2)}°`, hl: true });
            return { type: 'trig', degree: 0, solutions: [formatNum(degVal) + '°', formatNum(x2) + '°'], display: `x₁ = ${formatNum(degVal)}°  |  x₂ = ${formatNum(x2)}°` };
        }
        const x2 = -radVal;
        steps.push({ text: `✓ x₁ = ${formatNum(radVal)} rad  |  x₂ = ${formatNum(x2)} rad`, hl: true });
        return { type: 'trig', degree: 0, solutions: [formatNum(radVal) + ' rad', formatNum(x2) + ' rad'], display: `x₁ = ${formatNum(radVal)} rad  |  x₂ = ${formatNum(x2)} rad` };
    } else {
        if (useDeg) {
            steps.push({ text: `x = arctan(${formatNum(a)}) = ${formatNum(degVal)}°`, hl: false });
            steps.push({ text: `✓ x = ${formatNum(degVal)}°`, hl: true });
            return { type: 'trig', degree: 0, solutions: [formatNum(degVal) + '°'], display: `x = ${formatNum(degVal)}°` };
        }
        steps.push({ text: `✓ x = ${formatNum(radVal)} rad`, hl: true });
        return { type: 'trig', degree: 0, solutions: [formatNum(radVal) + ' rad'], display: `x = ${formatNum(radVal)} rad` };
    }
}

// —— 主入口 ——
export function solveEquation(equationStr: string, useDegrees: boolean): { steps: SolveStep[]; result: SolveResult } {
    const steps: SolveStep[] = [];

    let eq = equationStr.replace(/\s/g, '').toLowerCase();
    const parts = eq.split('=');
    if (parts.length !== 2) throw new Error("请输入正确的方程格式（含=）");

    const left = parts[0] || '0';
    const right = parts[1] || '0';
    steps.push({ text: `原方程: ${left} = ${right}`, hl: false });

    // 非多项式检测
    let m = left.match(/^sqrt\((.+)\)$/) || left.match(/^√\((.+)\)$/);
    if (m) return { steps, result: solveRadical(m[1], right, steps) };

    m = left.match(/^(.+)\/x\s*([+-].+)?$/);
    if (m && !left.includes('^') && !left.includes('sqrt') && !left.includes('sin') && !left.includes('cos') && !left.includes('tan') && !left.includes('ln') && !left.includes('abs')) {
        return { steps, result: solveRational(left, right, steps) };
    }

    if (/^[\d.]+?\^x$/.test(left) && /^[\d.+-]+$/.test(right)) {
        return { steps, result: solveExponential(left, right, steps) };
    }

    if (/^ln\(x\)$/.test(left) && /^[\d.+-]+$/.test(right)) {
        return { steps, result: solveLogarithmic(right, steps) };
    }

    m = left.match(/^abs\((.+)\)$/) || left.match(/^\|(.+)\|$/);
    if (m && /^[\d.+-]+$/.test(right)) {
        return { steps, result: solveAbsolute(m[1], right, steps) };
    }

    m = left.match(/^(sin|cos|tan)\((.+)\)$/);
    if (m && /^[\d.+-]+$/.test(right)) {
        return { steps, result: solveTrig(m[1], m[2], right, steps, useDegrees) };
    }

    // 多项式求解
    const combinedExpr = `(${left})-(${right})`;
    steps.push({ text: `移项: ${combinedExpr} = 0`, hl: false });

    const poly = parsePolynomial(combinedExpr);
    const [c, b, a, a3] = poly.coeffs;

    const eps = 1e-10;
    let degree = 0;
    if (Math.abs(a3) > eps) degree = 3;
    else if (Math.abs(a) > eps) degree = 2;
    else if (Math.abs(b) > eps) degree = 1;

    const simplified = fmtPoly([a3, a, b, c], ['x^3', 'x^2', 'x', '']);
    steps.push({ text: `化简: ${simplified} = 0`, hl: true });

    let result: SolveResult;
    if (degree === 3) result = solveCubic(a3, a, b, c, steps);
    else if (degree === 2) result = solveQuadratic(a, b, c, steps);
    else if (degree === 1) result = solveLinear(b, c, steps);
    else if (Math.abs(c) < eps) {
        result = { type: 'identity', degree: 0, solutions: [], display: '恒等式，任意 x 均成立' };
        steps.push({ text: '0 = 0，恒等式，任意 x 均成立', hl: false });
    } else {
        result = { type: 'contradiction', degree: 0, solutions: [], display: '矛盾方程，无解' };
        steps.push({ text: `${formatNum(c)} = 0，矛盾，无解`, hl: false });
    }

    return { steps, result };
}
