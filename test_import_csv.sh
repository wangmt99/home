#!/bin/bash
# ============================================================
# import_csv.txt 核心功能单元测试脚本
# 测试内容：split_line / process_value / in_list / 字段对齐 / 自定义分隔符
# ============================================================

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# -------- 从主脚本复制的核心函数 --------

# 按指定分隔符拆分一行，处理双引号内的分隔符和空值
# 参数: line delimiter
# 结果存入全局数组 VALUES_ARRAY
split_line() {
    local line=$1
    local delim=${2:-|~}
    VALUES_ARRAY=()
    local field=""
    local i=0
    local len=${#line}
    local delim_len=${#delim}
    local in_field_quote=0

    while [ $i -lt $len ]; do
        local char="${line:$i:1}"

        if [ "$in_field_quote" -eq 0 ] && [ ${#field} -eq 0 ] && [ "$char" = '"' ]; then
            in_field_quote=1
            i=$((i + 1))
            continue
        fi

        if [ "$in_field_quote" -eq 1 ] && [ "$char" = '"' ]; then
            local next_char=""
            if [ $((i + 1)) -lt $len ]; then
                next_char="${line:$((i + 1)):1}"
            fi
            if [ "$next_char" = '"' ]; then
                field+='"'
                i=$((i + 2))
                continue
            else
                in_field_quote=0
                i=$((i + 1))
                continue
            fi
        fi

        if [ "$in_field_quote" -eq 0 ] && [ $((i + delim_len)) -le $len ]; then
            local candidate="${line:$i:$delim_len}"
            if [ "$candidate" = "$delim" ]; then
                VALUES_ARRAY+=("$field")
                field=""
                i=$((i + delim_len))
                continue
            fi
        fi

        field+="$char"
        i=$((i + 1))
    done

    VALUES_ARRAY+=("$field")
}

is_numeric() {
    local val=$1
    if [[ "$val" =~ ^-?[0-9]+([.][0-9]+)?$ ]]; then
        return 0
    fi
    return 1
}

process_value() {
    local field_type=$1
    local val=$2

    val="${val#"${val%%[![:space:]]*}"}"
    val="${val%"${val##*[![:space:]]}"}"

    if [ -z "$val" ]; then
        echo "''"
        return
    fi

    local _sq="'"
    local _dq="''"

    case "$field_type" in
        NUMBER*)
            if is_numeric "$val"; then
                echo "$val"
            else
                echo "''"
            fi
            ;;
        DATE*)
            val="${val//$_sq/$_dq}"
            echo "TO_DATE('${val}', 'YYYY/MM/DD HH24:MI:SS')"
            ;;
        TIMESTAMP*)
            val="${val//$_sq/$_dq}"
            echo "TO_TIMESTAMP('${val}', 'YYYY/MM/DD HH24:MI:SS.FF')"
            ;;
        CHAR*|VARCHAR*|NVARCHAR*|CLOB*)
            val="${val//$_sq/$_dq}"
            echo "'$val'"
            ;;
        *)
            val="${val//$_sq/$_dq}"
            echo "'$val'"
            ;;
    esac
}

in_list() {
    local target=$1
    local list=$2
    [ -z "$list" ] && return 1
    for item in $list; do
        if [ "$item" = "$target" ]; then
            return 0
        fi
    done
    return 1
}

# -------- 测试框架 --------
TEST_PASS=0
TEST_FAIL=0

assert_eq() {
    local desc=$1
    local expected=$2
    local actual=$3
    if [ "$expected" = "$actual" ]; then
        echo "  [PASS] $desc"
        TEST_PASS=$((TEST_PASS + 1))
    else
        echo "  [FAIL] $desc"
        echo "    期望: $expected"
        echo "    实际: $actual"
        TEST_FAIL=$((TEST_FAIL + 1))
    fi
}

assert_array_eq() {
    local desc=$1
    shift
    local expected_count=$1
    shift
    local expected_list=("$@")

    local actual_count=${#VALUES_ARRAY[@]}

    if [ "$expected_count" -ne "$actual_count" ]; then
        echo "  [FAIL] $desc"
        echo "    期望元素数: $expected_count"
        echo "    实际元素数: $actual_count"
        echo "    实际值: ${VALUES_ARRAY[*]}"
        TEST_FAIL=$((TEST_FAIL + 1))
        return
    fi

    local all_ok=1
    for ((i=0; i<expected_count; i++)); do
        if [ "${expected_list[$i]}" != "${VALUES_ARRAY[$i]}" ]; then
            all_ok=0
            break
        fi
    done

    if [ "$all_ok" -eq 1 ]; then
        echo "  [PASS] $desc"
        TEST_PASS=$((TEST_PASS + 1))
    else
        echo "  [FAIL] $desc"
        echo "    期望: ${expected_list[*]}"
        echo "    实际: ${VALUES_ARRAY[*]}"
        TEST_FAIL=$((TEST_FAIL + 1))
    fi
}

# ============================================================
# 测试用例
# ============================================================

echo "============================================================"
echo "  测试1: split_line 函数 - 基础拆分"
echo "============================================================"

echo ""
echo "--- 1.1 简单三字段 ---"
split_line "a|~b|~c" "|~"
assert_array_eq "三字段简单拆分" 3 "a" "b" "c"

echo ""
echo "--- 1.2 开头空值 ---"
split_line "|~b|~c" "|~"
assert_array_eq "第一个字段为空" 3 "" "b" "c"

echo ""
echo "--- 1.3 中间空值 ---"
split_line "a|~|~c" "|~"
assert_array_eq "中间字段为空" 3 "a" "" "c"

echo ""
echo "--- 1.4 结尾空值 ---"
split_line "a|~b|~" "|~"
assert_array_eq "最后一个字段为空" 3 "a" "b" ""

echo ""
echo "--- 1.5 连续空值 ---"
split_line "|~|~|~" "|~"
assert_array_eq "全部为空（4个空字段）" 4 "" "" "" ""

echo ""
echo "--- 1.6 单字段 ---"
split_line "hello" "|~"
assert_array_eq "只有一个字段（无分隔符）" 1 "hello"

echo ""
echo "--- 1.7 空行 ---"
split_line "" "|~"
assert_array_eq "空行（一个空字段）" 1 ""

echo ""
echo "============================================================"
echo "  测试2: split_line 函数 - 双引号处理"
echo "============================================================"

echo ""
echo "--- 2.1 双引号内的分隔符不分割 ---"
split_line 'a|~"b|~c"|~d' "|~"
assert_array_eq "引号内的|~不分割" 3 "a" "b|~c" "d"

echo ""
echo "--- 2.2 双引号转义（两个双引号） ---"
split_line 'a|~"b""c"|~d' "|~"
assert_array_eq '两个双引号转义为一个' 3 "a" 'b"c' "d"

echo ""
echo "--- 2.3 全字段带引号 ---"
split_line '"a"|~"b"|~"c"' "|~"
assert_array_eq "所有字段都带引号" 3 "a" "b" "c"

echo ""
echo "--- 2.4 引号内有多个分隔符 ---"
split_line 'id|~"x|~y|~z"|~end' "|~"
assert_array_eq "引号内多个分隔符" 3 "id" "x|~y|~z" "end"

echo ""
echo "--- 2.5 空字符串双引号 ---"
split_line 'a|~""|~c' "|~"
assert_array_eq "空字符串用双引号表示" 3 "a" "" "c"

echo ""
echo "--- 2.6 混合空值和引号 ---"
split_line '|~"quoted"|~|~""|~' "|~"
assert_array_eq "混合空值与引号" 5 "" "quoted" "" "" ""

echo ""
echo "============================================================"
echo "  测试3: process_value 函数 - 空值处理（统一空字符串）"
echo "============================================================"

echo ""
echo "--- 3.1 NUMBER 空值 ---"
result=$(process_value "NUMBER" "")
assert_eq "NUMBER空值返回空字符串" "''" "$result"

echo ""
echo "--- 3.2 DATE 空值 ---"
result=$(process_value "DATE" "")
assert_eq "DATE空值返回空字符串" "''" "$result"

echo ""
echo "--- 3.3 TIMESTAMP 空值 ---"
result=$(process_value "TIMESTAMP" "")
assert_eq "TIMESTAMP空值返回空字符串" "''" "$result"

echo ""
echo "--- 3.4 VARCHAR2 空值 ---"
result=$(process_value "VARCHAR2" "")
assert_eq "VARCHAR2空值返回空字符串" "''" "$result"

echo ""
echo "--- 3.5 CLOB 空值 ---"
result=$(process_value "CLOB" "")
assert_eq "CLOB空值返回空字符串" "''" "$result"

echo ""
echo "--- 3.6 带空格的空值 ---"
result=$(process_value "VARCHAR2" "   ")
assert_eq "带空格的空值也返回空字符串" "''" "$result"

echo ""
echo "============================================================"
echo "  测试4: process_value 函数 - 各类型正常值"
echo "============================================================"

echo ""
echo "--- 4.1 NUMBER 整数 ---"
result=$(process_value "NUMBER" "123")
assert_eq "NUMBER整数" "123" "$result"

echo ""
echo "--- 4.2 NUMBER 小数 ---"
result=$(process_value "NUMBER" "123.45")
assert_eq "NUMBER小数" "123.45" "$result"

echo ""
echo "--- 4.3 NUMBER 负数 ---"
result=$(process_value "NUMBER" "-99")
assert_eq "NUMBER负数" "-99" "$result"

echo ""
echo "--- 4.4 NUMBER 非数字 ---"
result=$(process_value "NUMBER" "abc")
assert_eq "NUMBER非数字返回空字符串" "''" "$result"

echo ""
echo "--- 4.5 DATE 正常日期 ---"
result=$(process_value "DATE" "2025/01/15 10:30:00")
assert_eq "DATE格式YYYY/MM/DD" "TO_DATE('2025/01/15 10:30:00', 'YYYY/MM/DD HH24:MI:SS')" "$result"

echo ""
echo "--- 4.6 TIMESTAMP 正常时间戳 ---"
result=$(process_value "TIMESTAMP" "2025/01/15 10:30:00.123456")
assert_eq "TIMESTAMP格式YYYY/MM/DD" "TO_TIMESTAMP('2025/01/15 10:30:00.123456', 'YYYY/MM/DD HH24:MI:SS.FF')" "$result"

echo ""
echo "--- 4.7 VARCHAR2 普通字符串 ---"
result=$(process_value "VARCHAR2" "hello")
assert_eq "VARCHAR2字符串" "'hello'" "$result"

echo ""
echo "--- 4.8 VARCHAR2 含单引号 ---"
result=$(process_value "VARCHAR2" "it's")
assert_eq "单引号转义" "'it''s'" "$result"

echo ""
echo "--- 4.9 CHAR 类型 ---"
result=$(process_value "CHAR" "Y")
assert_eq "CHAR类型" "'Y'" "$result"

echo ""
echo "--- 4.10 NVARCHAR2 类型 ---"
result=$(process_value "NVARCHAR2" "测试")
assert_eq "NVARCHAR2类型" "'测试'" "$result"

echo ""
echo "--- 4.11 未知类型 ---"
result=$(process_value "BLOB" "data")
assert_eq "未知类型按字符串处理" "'data'" "$result"

echo ""
echo "============================================================"
echo "  测试5: in_list 函数"
echo "============================================================"

echo ""
echo "--- 5.1 存在于列表 ---"
in_list "a.csv" "a.csv b.csv c.csv"
assert_eq "a.csv在列表中" "0" "$?"

echo ""
echo "--- 5.2 不存在于列表 ---"
in_list "d.csv" "a.csv b.csv c.csv"
assert_eq "d.csv不在列表中" "1" "$?"

echo ""
echo "--- 5.3 空列表 ---"
in_list "a.csv" ""
assert_eq "空列表返回1" "1" "$?"

echo ""
echo "--- 5.4 单元素列表 ---"
in_list "test.csv" "test.csv"
assert_eq "单元素匹配" "0" "$?"

echo ""
echo "============================================================"
echo "  测试6: 完整行 INSERT 语句生成"
echo "============================================================"

# 模拟一行数据的完整处理
fields=("ID" "NAME" "AGE" "CREATE_TIME")
types=("NUMBER" "VARCHAR2" "NUMBER" "DATE")

echo ""
echo "--- 6.1 完整行处理 ---"
line='1|~张三|~25|~2025/01/01 10:00:00'
split_line "$line" "|~"

values=""
for idx in "${!fields[@]}"; do
    val="${VALUES_ARRAY[$idx]:-}"
    processed=$(process_value "${types[$idx]}" "$val")
    if [ -z "$values" ]; then
        values="$processed"
    else
        values="$values, $processed"
    fi
done

assert_eq "完整行值拼接" "1, '张三', 25, TO_DATE('2025/01/01 10:00:00', 'YYYY/MM/DD HH24:MI:SS')" "$values"

echo ""
echo "--- 6.2 含空值的完整行 ---"
line='|~|~|~'
split_line "$line" "|~"

values=""
for idx in "${!fields[@]}"; do
    val="${VALUES_ARRAY[$idx]:-}"
    processed=$(process_value "${types[$idx]}" "$val")
    if [ -z "$values" ]; then
        values="$processed"
    else
        values="$values, $processed"
    fi
done

assert_eq "全部为空值" "'', '', '', ''" "$values"

echo ""
echo "--- 6.3 带双引号的行 ---"
line='1|~"张|~三"|~28|~2025/03/15 09:00:00'
split_line "$line" "|~"

values=""
for idx in "${!fields[@]}"; do
    val="${VALUES_ARRAY[$idx]:-}"
    processed=$(process_value "${types[$idx]}" "$val")
    if [ -z "$values" ]; then
        values="$processed"
    else
        values="$values, $processed"
    fi
done

assert_eq "引号内分隔符不分割" "1, '张|~三', 28, TO_DATE('2025/03/15 09:00:00', 'YYYY/MM/DD HH24:MI:SS')" "$values"

echo ""
echo "============================================================"
echo "  测试7: 字段数对齐（以表头字段数为准）"
echo "============================================================"

# 模拟表头字段数
test_align_fields() {
    local desc=$1
    local expected_count=$2
    local field_count=$3
    local line=$4
    local expected_values=$5
    local delim=${6:-|~}

    split_line "$line" "$delim"

    local actual_count=${#VALUES_ARRAY[@]}
    if [ "$actual_count" -gt "$field_count" ]; then
        VALUES_ARRAY=("${VALUES_ARRAY[@]:0:$field_count}")
    elif [ "$actual_count" -lt "$field_count" ]; then
        local pad_i
        for ((pad_i=actual_count; pad_i<field_count; pad_i++)); do
            VALUES_ARRAY+=("")
        done
    fi

    local result=""
    for ((i=0; i<field_count; i++)); do
        if [ -z "$result" ]; then
            result="[${VALUES_ARRAY[$i]}]"
        else
            result="$result [${VALUES_ARRAY[$i]}]"
        fi
    done

    if [ "${#VALUES_ARRAY[@]}" -eq "$expected_count" ] && [ "$result" = "$expected_values" ]; then
        echo "  [PASS] $desc"
        TEST_PASS=$((TEST_PASS + 1))
    else
        echo "  [FAIL] $desc"
        echo "    期望字段数: $expected_count"
        echo "    实际字段数: ${#VALUES_ARRAY[@]}"
        echo "    期望: $expected_values"
        echo "    实际: $result"
        TEST_FAIL=$((TEST_FAIL + 1))
    fi
}

echo ""
echo "--- 7.1 数据行末尾多一个 |~，表头4字段 ---"
test_align_fields "末尾多余|~被截断" 4 4 'a|~b|~c|~d|~' '[a] [b] [c] [d]'

echo ""
echo "--- 7.2 数据行末尾多两个 |~，表头4字段 ---"
test_align_fields "末尾多个|~被截断" 4 4 'a|~b|~c|~d|~|~' '[a] [b] [c] [d]'

echo ""
echo "--- 7.3 数据行字段数不足，表头4字段 ---"
test_align_fields "字段不足补空" 4 4 'a|~b' '[a] [b] [] []'

echo ""
echo "--- 7.4 数据行字段数刚好，表头4字段 ---"
test_align_fields "字段数刚好一致" 4 4 'a|~b|~c|~d' '[a] [b] [c] [d]'

echo ""
echo "--- 7.5 表头3字段，数据行4个字段（末尾多|~） ---"
test_align_fields "表头3字段数据行多1个" 3 3 'x|~y|~z|~' '[x] [y] [z]'

echo ""
echo "--- 7.6 带引号的行末尾多 |~ ---"
test_align_fields "引号行末尾多|~被截断" 4 4 '1|~"a|~b"|~3|~2025/01/01|~' '[1] [a|~b] [3] [2025/01/01]'

echo ""
echo "============================================================"
echo "  测试8: 自定义分隔符"
echo "============================================================"

echo ""
echo "--- 8.1 单字符分隔符逗号 ---"
split_line "a,b,c" ","
assert_array_eq "逗号分隔三字段" 3 "a" "b" "c"

echo ""
echo "--- 8.2 三字符分隔符 ### ---"
split_line "a###b###c" "###"
assert_array_eq "三字符分隔符" 3 "a" "b" "c"

echo ""
echo "--- 8.3 自定义分隔符中间空值 ---"
split_line "a####c" "##"
assert_array_eq "中间空值（两个分隔符相邻）" 3 "a" "" "c"

echo ""
echo "--- 8.4 自定义分隔符末尾多余 ---"
split_line "a##b##" "##"
assert_array_eq "末尾多余分隔符" 3 "a" "b" ""

echo ""
echo "--- 8.5 自定义分隔符+双引号 ---"
split_line 'a##"x##y"##z' "##"
assert_array_eq "引号内分隔符不分割" 3 "a" "x##y" "z"

echo ""
echo "--- 8.6 单字符竖线分隔符 ---"
split_line "a|b|c" "|"
assert_array_eq "单字符竖线" 3 "a" "b" "c"

echo ""
echo "--- 8.7 未传分隔符默认 |~ ---"
split_line "a|~b|~c"
assert_array_eq "未传分隔符使用默认|~" 3 "a" "b" "c"

echo ""
echo "============================================================"
echo "  测试9: 脚本整体语法检查"
echo "============================================================"
echo ""
bash -n "$SCRIPT_DIR/import_csv.txt"
if [ $? -eq 0 ]; then
    echo "  [PASS] 脚本语法检查通过"
    TEST_PASS=$((TEST_PASS + 1))
else
    echo "  [FAIL] 脚本语法检查失败"
    TEST_FAIL=$((TEST_FAIL + 1))
fi

echo ""
echo "============================================================"
echo "  测试结果汇总"
echo "============================================================"
echo ""
echo "  通过: $TEST_PASS"
echo "  失败: $TEST_FAIL"
echo ""
if [ "$TEST_FAIL" -eq 0 ]; then
    echo "  所有测试通过！"
else
    echo "  有测试失败，请检查！"
fi
echo ""
echo "============================================================"
