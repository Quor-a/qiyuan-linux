# expect: 10
# if / else if / else 链：grade(85)=2, 95->1, 65->3, 10->4
fn grade(s: i64) -> i64 {
    if s >= 90 {
        return 1;
    } else if s >= 80 {
        return 2;
    } else if s >= 60 {
        return 3;
    } else {
        return 4;
    }
    return 0;
}

fn main() -> i64 {
    return grade(85) + grade(95) + grade(65) + grade(10);
}
