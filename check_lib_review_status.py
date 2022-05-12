import os

assert __name__ == '__main__'

reviewed_count = 0
total_count = 0

def check_dir(d: str, depth: int=0):
    global reviewed_count, total_count

    for file in os.listdir(d):
        filepath = f"{d}/{file}"
        if file.endswith(".dart"):
            if file == "ink_flutter_runtime.dart":
                continue
            with open(filepath) as f:
                reviewed: bool = f.read().startswith("// reviewed")
                reviewed_count += int(reviewed)
                total_count += 1
                print(filepath + ((" (√)") if reviewed else ""))
        else:
            check_dir(filepath, depth=depth+1)

check_dir("lib")

print(f"progress: {reviewed_count}/{total_count}")