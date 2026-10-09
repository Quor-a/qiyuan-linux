fn qat(x: f64) -> f64 {
    let neg: i64 = 0;
    let v: f64 = x;
    if v < 0.0 { v = -v; neg = 1; }
    let inv: i64 = 0;
    if v > 1.0 { v = 1.0 / v; inv = 1; }
    let red: i64 = 0;
    if v > 0.6 { v = (v - 1.0) / (v + 1.0); red = 1; }
    let sum: f64 = 0.0;
    let term: f64 = v;
    let v2: f64 = v * v;
    let n: i64 = 1;
    let sign: i64 = 1;
    while n < 40 {
        if sign == 1 {
            sum = sum + term / itof(n);
        } else {
            sum = sum - term / itof(n);
        }
        term = term * v2;
        sign = -sign;
        n = n + 2;
    }
    if red == 1 { sum = 0.7853981633974483 + sum; }
    if inv == 1 { sum = 1.5707963267948966 - sum; }
    if neg == 1 { sum = -sum; }
    return sum;
}

fn qexp(x: f64) -> f64 {
    let k: i64 = 0;
    let t: f64 = x;
    while t > 0.5 { t = t / 2.0; k = k + 1; }
    while t < -1.0 { t = t * 2.0; k = k - 1; }
    let sum: f64 = 1.0;
    let term: f64 = 1.0;
    let n: i64 = 1;
    while n < 24 {
        term = term * t / itof(n);
        sum = sum + term;
        n = n + 1;
    }
    while k > 0 { sum = sum * sum; k = k - 1; }
    while k < 0 { sum = sum * 0.5; k = k + 1; }
    return sum;
}

fn qlog(x: f64) -> f64 {
    # ln x = 2*atanh(m)，m=(x-1)/(x+1)，先缩到 [0.7,1.4]
    let k: f64 = 0.0;
    let v: f64 = x;
    while v > 1.4 { v = v / 2.0; k = k + 1.0; }
    while v < 0.7 { v = v * 2.0; k = k - 1.0; }
    let m: f64 = (v - 1.0) / (v + 1.0);
    let m2: f64 = m * m;
    let sum: f64 = 0.0;
    let term: f64 = m;
    let n: i64 = 1;
    while n < 40 {
        sum = sum + term / itof(n);
        term = term * m2;
        n = n + 2;
    }
    return 2.0 * sum + k * 0.6931471805599453;
}

fn qpow(x: f64, y: f64) -> f64 {
    return qexp(y * qlog(x));
}
fn qsqrt(x: f64) -> f64 {
    if x == 0.0 { return 0.0; }
    let y: f64 = 1.0;
    let i: i64 = 0;
    while i < 40 {
        y = (y + x / y) / 2.0;
        i = i + 1;
    }
    return y;
}
fn qsin(x: f64) -> f64 {
    let sum: f64 = 0.0;
    let term: f64 = x;
    let n: i64 = 1;
    while n < 34 {
        sum = sum + term;
        term = term * (-(x * x)) / (itof(n + 1) * itof(n + 2));
        n = n + 2;
    }
    return sum;
}
fn qcos(x: f64) -> f64 {
    let sum: f64 = 0.0;
    let term: f64 = 1.0;
    let n: i64 = 0;
    while n < 34 {
        sum = sum + term;
        term = term * (-(x * x)) / (itof(n + 1) * itof(n + 2));
        n = n + 2;
    }
    return sum;
}
fn qtan(x: f64) -> f64 { return qsin(x) / qcos(x); }
