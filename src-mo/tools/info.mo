# info —— 查看文件魔数与元数据（mo.sh info 的实现）
import "io.mo";
import "binfmt.mo";
import "dir.mo";

fn main() -> i64 {
    if argc() < 2 {
        print("usage: mo info <file>\n");
        return 2;
    }
    let n: i64 = magic_load(argv(1), 512);
    if n < 0 {
        print("cannot open: ");
        print(argv(1));
        print_nl();
        return 1;
    }
    print(argv(1));
    print(": ");
    print(magic_name());
    if elf_is() == 1 {
        print("  ");
        print(elf_machine_name());
        print(" ");
        print(elf_type_name());
        print(" class=");
        print_i64(elf_class());
        print(" shnum=");
        print_i64(elf_shnum());
        print(" entry=");
        print_hex(elf_entry());
    }
    print("  size=");
    print_i64(stat_size(argv(1)));
    print_nl();
    return 0;
}
