/** 方程求解结果类型 */
export interface SolveResult {
    type: string;
    degree: number;
    solutions: string[];
    display: string;
    a?: number;
    b?: number;
    c?: number;
    a3?: number;
    delta?: number;
}

/** 解题步骤 */
export interface SolveStep {
    text: string;
    hl: boolean;
}

/** 多项式系数对象 */
export interface PolyCoeffs {
    a3: number;
    a2: number;
    a1: number;
    a0: number;
    coeffs: [number, number, number, number];
}

/** 历史记录项 */
export interface HistoryItem {
    id: number;
    source: string;
    input: string;
    nums: number[];
    count: number;
    sum: number;
    avg: number;
    time: string;
}
