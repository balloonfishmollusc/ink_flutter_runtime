import re, json

with open("test/Tests.cs") as f:
    cs_tests = re.sub(r"\s", "", string=f.read())

with open("test/ink_flutter_runtime_test.dart") as f:
    dart_tests = re.sub(r"\s", "", string=f.read())

cs_pattern = re.compile(r"(\[\w*?Test\(\)\])publicvoid(\w+?)\(\)")
dart_pattern = re.compile(r'test\("(\w+)",')


cs_stats = cs_pattern.findall(cs_tests)
cs_names = {name for _, name in cs_stats}
dart_stats = dart_pattern.findall(dart_tests)

# total cs tests
# ignored cs tests

results = {
    "cs_tags": list({tag for tag, _ in cs_stats}),
    "cs_total_tests": sum([1 for tag, _ in cs_stats if tag != '[xTest()]']),
    "cs_marked_tests": sum([1 for tag, _ in cs_stats if tag in ('[okTest()]', '[errorTest()]')]),
    "cs_error_tests": [name for tag, name in cs_stats if tag == '[errorTest()]'],
    "dart_done_tests": sum([1 for name in dart_stats if name in cs_names]),
}

results['progress'] = f"{results['dart_done_tests']} / {results['cs_total_tests']} ({int(results['dart_done_tests']/results['cs_total_tests']*100)}%)"

# results['diff'] = list(set([name for name in dart_stats if name in cs_names]).difference(set([name for tag, name in cs_stats if tag in ('[okTest()]', '[errorTest()]')])))

print(json.dumps(results, indent=4))