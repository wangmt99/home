# Oracle CSV 批量导入工具说明文档

## 一、概述

本工具用于将 CSV 文件批量导入 Oracle 数据库。支持多用户、多路径、多文件筛选，自动按字段类型处理数据，支持双引号转义、空值处理、自定义分隔符、字段数对齐、批量提交、错误跳过、独立日志记录、中文字符编码转换、并行处理等功能。

---

## 二、文件清单

| 文件名 | 说明 |
|---|---|
| `import_csv.conf` | 配置文件，存放数据库连接、用户路径、文件筛选、分隔符、编码、日志路径、并发配置 |
| `import_csv.txt` | 主执行脚本（Bash），后台运行 |
| `test_import_csv.sh` | 单元测试脚本，验证核心函数逻辑 |
| `import_csv.md` | 本说明文档 |

---

## 三、配置文件说明（`import_csv.conf`）

### 1. 数据库连接配置

| 配置项 | 说明 |
|---|---|
| `DB_HOST` | 数据库主机地址 |
| `DB_PORT` | 数据库端口 |
| `DB_SERVICE` | 数据库服务名（SID 或 Service Name） |

### 2. 字符编码配置

| 配置项 | 说明 | 默认值 |
|---|---|---|
| `NLS_LANG` | 数据库字符集，用于解决中文乱码问题 | `SIMPLIFIED CHINESE_CHINA.ZHS16GBK` |
| `CSV_FILE_ENCODING` | CSV 文件编码（脚本读取时使用的源编码） | 与系统 locale 一致 |
| `SQL_FILE_ENCODING` | SQL 文件编码（执行 sqlplus 前的目标编码） | 与 NLS_LANG 保持一致 |

常见 `NLS_LANG` 取值：

| 值 | 说明 |
|---|---|
| `SIMPLIFIED CHINESE_CHINA.ZHS16GBK` | 数据库为 GBK 编码 |
| `SIMPLIFIED CHINESE_CHINA.AL32UTF8` | 数据库为 UTF-8 编码 |
| `AMERICAN_AMERICA.AL32UTF8` | 英文环境 UTF-8 |

### 3. 用户配置

| 用户标签 | 用户名 | 密码 | CSV 路径 |
|---|---|---|---|
| nlp | `NLP_USER` | `NLP_PASSWORD` | `NLP_CSV_PATH` |
| stg | `STG_USER` | `STG_PASSWORD` | `STG_CSV_PATH` |

### 4. 文件筛选配置

| 配置项 | 说明 | 示例 |
|---|---|---|
| `SPECIFIED_FILES` | 指定导入文件，`*` 表示全部，空格分隔多个，空值直接退出 | `*` / `a.csv b.csv` |
| `SKIP_FILES` | 不需要执行的文件，空格分隔多个 | `test.csv temp.csv` |
| `INSERT_ONLY_FILES` | 仅 INSERT 不 TRUNCATE 的文件，空格分隔多个 | `log.csv` |
| `FIELD_DELIMITER` | 字段间组合分隔符，不设置时默认值为 `|~` | `|~` / `##` / `,` |

### 5. 日志路径配置

| 配置项 | 说明 |
|---|---|
| `BATCH_LOG_PATH` | 批处理汇总日志目录 |
| `FILE_LOG_PATH` | 每个导入文件的独立日志目录 |

### 6. 并发配置

| 配置项 | 说明 | 默认值 |
|---|---|---|
| `MAX_PARALLEL` | 最大并发数（同时生成 SQL 或执行 SQL 的任务数） | `1`（串行） |

- 值为 `1` 时为串行执行
- 建议值 `2-4`，过大会增加数据库压力
- 并发控制作用于两个阶段：SQL 生成和 SQL 执行

---

## 四、脚本执行流程

```
1. 加载配置文件 + 设置 Locale（UTF-8 自动检测）
       ↓
2. 检查配置项是否完整
       ↓
3. 自动 fork 到后台运行（交互式终端时）
       ↓
4. 步骤0：检查 SQL*Plus 客户端是否安装
       ↓
5. 步骤1：预先检查所有用户数据库连通性（SELECT 1 FROM DUAL）
       ↓
6. 步骤2：检查 SPECIFIED_FILES 是否为空 → 空则直接退出
       ↓
7. 预检查所有用户的可导入文件数量 → 0 则直接退出
       ↓
8. 步骤3：并行生成 SQL 文件（受 MAX_PARALLEL 控制）
       ├─ CSV 文件按 CSV_FILE_ENCODING 解码读取
       ├─ awk 在 UTF-8 locale 下处理中文
       ├─ 生成 INSERT 语句（多行格式，避免缓冲区溢出）
       ├─ SQL 文件按 SQL_FILE_ENCODING 编码输出
       └─ 每个文件独立日志记录
       ↓
9. 步骤4：并行执行 SQL 文件（受 MAX_PARALLEL 控制）
       ├─ sqlplus 连接数据库执行
       ├─ sqlplus 输出通过 iconv 转换为 UTF-8 记录日志
       ├─ 错误行跳过并记录
       └─ 每万行 COMMIT 一次
       ↓
10. 写入批处理汇总日志
       ↓
11. 完成
```

---

## 五、编码处理流程

```
UTF-8 CSV 文件
    │
    ▼ iconv -f $CSV_FILE_ENCODING -t UTF-8
    │
UTF-8 数据流（管道传入 awk）
    │
    ▼ awk 处理（LC_ALL=C.UTF-8 或自动检测的 UTF-8 locale）
    │
UTF-8 SQL 文件
    │
    ▼ iconv -f UTF-8 -t $SQL_FILE_ENCODING
    │
GBK SQL 文件（与 NLS_LANG 匹配）
    │
    ▼ sqlplus 执行（NLS_LANG=SIMPLIFIED CHINESE_CHINA.ZHS16GBK）
    │
GBK 输出（错误信息等）
    │
    ▼ iconv -f GBK -t UTF-8
    │
UTF-8 日志文件
```

### Locale 自动检测

脚本启动时自动检测可用的 UTF-8 locale，按以下优先级查找：

```
C.UTF-8 → en_US.UTF-8 → zh_CN.UTF-8 → en_US.utf8 → zh_CN.utf8 → 任意含 utf-8 的 locale
```

---

## 六、并行处理机制

### 并发流程示意

```
MAX_PARALLEL=1（串行）:  [文件A] → [文件B] → [文件C] → [文件D]

MAX_PARALLEL=2:  [文件A] → [文件C]
                 [文件B] → [文件D]

MAX_PARALLEL=4:  [文件A]
                 [文件B]
                 [文件C]
                 [文件D]
```

### 实现方式

- 每个任务在后台子shell `() &` 中执行
- `wait_for_slot` 函数控制并发数：后台任务数 >= `MAX_PARALLEL` 时等待
- 每个任务结果写入独立临时文件，避免变量竞争
- `wait` 等待全部完成后统一收集结果

---

## 七、CSV 文件格式要求

### 1. 文件名

- 文件名（去掉 `.csv` 后缀）即为 Oracle 表名
- 表名不区分大小写，脚本自动转为大写

### 2. 行分隔符

- 字段间分隔符：`|~`（可在配置文件中通过 `FIELD_DELIMITER` 自定义，支持任意长度）
- 双引号内的分隔符不被分割
- 双引号转义：`""` 表示一个双引号字符

### 3. 文件结构

```
第一行：字段名（与表字段对应，顺序一致）
第二行起：数据行
```

### 4. 字段数对齐

- 数据行字段数严格以表头字段数为准
- 多余字段（如末尾多余的 `|~`）会被截断
- 不足字段会补空字符串

### 5. 示例

```
ID|~NAME|~AGE|~CREATE_TIME
1|~张三|~25|~2025/01/01 10:00:00
2|~李四|~30|~2025/01/02 11:30:00
3|~"王|~五"|~28|~2025/01/03 09:00:00
4|~|~|~2025/01/04 12:00:00
5|~赵六|~22|~2025/01/05 08:00:00|~
```

说明：
- 第 3 行：双引号内的 `|~` 不分割，NAME 字段值为 `王|~五`
- 第 4 行：ID、NAME 为空，按字段类型处理为空字符串 `''`（不使用 NULL）
- 第 5 行：末尾多余的 `|~` 被截断，不影响导入
- 日期格式使用 `YYYY/MM/DD`

---

## 八、字段类型处理规则

脚本通过 `user_tab_columns` 获取字段类型，按类型处理值：

| 字段类型 | 空值处理 | 非空值处理 |
|---|---|---|
| NUMBER | `''`（空字符串） | 直接输出数字，非数字转 `''` |
| DATE | `''`（空字符串） | `TO_DATE('值', 'YYYY/MM/DD HH24:MI:SS')` |
| TIMESTAMP | `''`（空字符串） | `TO_TIMESTAMP('值', 'YYYY/MM/DD HH24:MI:SS.FF')` |
| VARCHAR / CHAR / NVARCHAR / CLOB | `''`（空字符串） | 单引号包裹，单引号转义为 `''` |
| 其他类型 | `''`（空字符串） | 单引号包裹，单引号转义为 `''` |

### 说明

- **空值统一按空字符串 `''` 处理**，不使用 `NULL`
- **日期格式统一使用 `YYYY/MM/DD`**（含时间部分 `YYYY/MM/DD HH24:MI:SS`）
- **日期数据示例**：`2025/01/01 10:00:00`

---

## 九、批处理提交

- 每导入 **10000 行** 自动执行一次 `COMMIT`
- 提交进度记录到单文件日志：`[INFO] 已提交 10000 行`
- 文件末尾统一 `COMMIT` 收尾

---

## 十、日志说明

### 1. 单文件日志

- **路径**：`$FILE_LOG_PATH/<用户名>_<表名>_<时间戳>.log`
- **内容**：
  - 文件处理开始/结束
  - 用户、表名、分隔符
  - 表/字段检查结果
  - 第2行 INSERT 语句示例（用于排查）
  - TRUNCATE 执行情况
  - 待导入行数
  - 每行错误信息（行号 + 错误内容）
  - 批量提交进度
  - 最终统计（总行数/插入量/错误量）

### 2. 批处理汇总日志

- **路径**：`$BATCH_LOG_PATH/batch_<时间戳>.log`
- **内容**：
  - 执行开始/结束时间
  - 数据库连接信息
  - SQL*Plus 客户端版本
  - 配置项摘要（含分隔符、并发数）
  - 步骤0/1/2/3/4 执行过程
  - 每个文件的处理结果：`用户|用户名|文件|表|删除标记|插入量|错误量|状态|开始时间|结束时间`
  - 汇总统计

---

## 十一、使用方法

### 1. 环境依赖

- Bash 4.0+
- Oracle Instant Client（含 `sqlplus`）
- `iconv`（编码转换，系统通常自带）
- 数据库用户需有 `SELECT` / `INSERT` / `TRUNCATE` 权限

### 2. 修改配置

编辑 `import_csv.conf`，填入实际的：

- 数据库地址、端口、服务名
- 字符编码（NLS_LANG、CSV_FILE_ENCODING、SQL_FILE_ENCODING）
- 各用户账号密码
- CSV 文件路径
- 字段分隔符（可选，默认 `|~`）
- 日志路径
- 文件筛选规则
- 并发数（可选，默认 `1` 串行）

### 3. 执行脚本

```bash
# 后台执行（默认）
./import_csv.txt
# 输出: 脚本已转入后台运行，PID: xxxx
#       批处理日志: /home/nlp/SH_ALL/logs/batch/batch_xxxxxx.log

# 前台调试（不自动转入后台）
IMPORT_CSV_BG=1 ./import_csv.txt
```

### 4. 查看日志

```bash
# 查看批处理汇总日志
tail -f /home/nlp/SH_ALL/logs/batch/batch_*.log

# 查看某文件导入日志
tail -f /home/nlp/SH_ALL/logs/files/TABLE_NAME_*.log
```

### 5. 运行单元测试

```bash
./test_import_csv.sh
```

---

## 十二、错误处理机制

| 错误场景 | 处理方式 |
|---|---|
| 配置文件缺失或必填项为空 | 立即退出 |
| SQL*Plus 客户端未安装 | 立即退出，提示安装 Oracle Instant Client |
| 数据库连接失败（预检查阶段） | 标记该用户为 FAIL，跳过该用户所有文件 |
| 表不存在 | 跳过该文件，记录单文件日志 |
| 字段缺失 | 跳过该文件，记录单文件日志 |
| TRUNCATE 失败 | 跳过该文件，记录单文件日志 |
| 单行 INSERT 失败 | 跳过该行，记录行号和错误信息，继续处理 |
| 批量提交失败 | 记录错误，继续后续处理 |
| SQL 文件编码转换失败 | 记录 [ERROR] 日志，提示检查 CSV 字符 |
| Locale 不可用 | 兜底设置 LC_CTYPE，降级处理 |

---

## 十三、配置文件示例

```ini
# -------------------- 数据库连接配置 --------------------
DB_HOST=192.168.1.100
DB_PORT=1521
DB_SERVICE=orcl

# -------------------- 字符编码配置 --------------------
NLS_LANG="SIMPLIFIED CHINESE_CHINA.ZHS16GBK"
CSV_FILE_ENCODING=UTF-8
SQL_FILE_ENCODING=GBK

# -------------------- nlp 用户配置 --------------------
NLP_USER=nlp
NLP_PASSWORD=nlp_password
NLP_CSV_PATH=/home/nlp/SH_ALL/csv_nlp

# -------------------- stg 用户配置 --------------------
STG_USER=stg
STG_PASSWORD=stg_password
STG_CSV_PATH=/home/nlp/SH_ALL/csv_stg

# -------------------- 文件筛选配置 --------------------
SPECIFIED_FILES=*
FIELD_DELIMITER=|~
SKIP_FILES=
INSERT_ONLY_FILES=

# -------------------- 日志路径配置 --------------------
BATCH_LOG_PATH=/home/nlp/SH_ALL/logs/batch
FILE_LOG_PATH=/home/nlp/SH_ALL/logs/files

# -------------------- 并发配置 --------------------
MAX_PARALLEL=2
```

---

## 十四、单元测试覆盖

`test_import_csv.sh` 共 51 个测试用例，覆盖：

| 测试组 | 用例数 | 内容 |
|---|---|---|
| 测试1: split_line 基础拆分 | 7 | 简单拆分、开头/中间/结尾空值、连续空值、单字段、空行 |
| 测试2: split_line 双引号 | 6 | 引号内分隔符不分割、双引号转义、全引号字段、多分隔符、空引号、混合 |
| 测试3: 空值处理 | 6 | NUMBER/DATE/TIMESTAMP/VARCHAR/CLOB 空值 + 带空格空值 |
| 测试4: 各类型正常值 | 11 | NUMBER 整数/小数/负数/非数字、DATE/TIMESTAMP、VARCHAR/CHAR/NVARCHAR、单引号转义 |
| 测试5: in_list | 4 | 存在/不存在/空列表/单元素 |
| 测试6: 完整 INSERT 语句 | 3 | 正常行、全空行、带双引号行 |
| 测试7: 字段数对齐 | 6 | 末尾多余/多个/不足/刚好/表头3字段/引号行末尾多余 |
| 测试8: 自定义分隔符 | 7 | 逗号/三字符/中间空/末尾空/双引号/竖线/默认分隔符 |
| 测试9: 脚本语法 | 1 | bash -n 语法检查 |

---

## 十五、注意事项

1. **CSV 文件第一行必须是字段名**，列顺序与表字段对应
2. **数据行中的单引号会被自动转义**，无需手动处理
3. **空值统一按空字符串 `''` 处理**，不使用 NULL（包括 NUMBER/DATE 等所有类型）
4. **日期格式统一使用 `YYYY/MM/DD`**，例如 `2025/01/01 10:00:00`
5. **双引号内的分隔符不会被分割**，但需用 `""` 转义双引号本身
6. **字段分隔符可自定义**，通过 `FIELD_DELIMITER` 配置，支持任意长度，未设置时默认 `|~`
7. **数据行字段数以表头为准**，多余截断，不足补空
8. **每万行提交一次**，避免事务过大导致回滚段不足
9. **错误行不影响其他行导入**，错误信息会精确到行号
10. **后台执行依赖 `nohup`**，关闭终端不影响任务运行
11. **数据库连通性会预先统一检查**，任一用户连接失败仅跳过该用户，不影响其他用户
12. **建议首次执行前用 `IMPORT_CSV_BG=1` 前台运行测试**
13. **编码三要素需匹配**：`CSV_FILE_ENCODING`（CSV 源编码）、`SQL_FILE_ENCODING`（SQL 输出编码）、`NLS_LANG`（数据库编码）
14. **并发数建议 2-4**，过大会增加数据库连接压力，`1` 为串行模式

---

## 十六、问题修复记录

以下为开发过程中遇到的问题及解决方案：

### 问题1：出站汉字乱码（sqlplus 输出中文乱码）

**现象**：日志中出现 `xCAxE4xC8xEBxB3xA4` 等十六进制乱码，无法阅读 sqlplus 的中文错误信息。

**原因**：`NLS_LANG=ZHS16GBK` 时，sqlplus 的所有输出（包括错误信息）都是 GBK 编码，但日志文件在 UTF-8 环境下创建，GBK 字节直接写入导致乱码。

**解决方案**：在 `execute_sql_file` 函数中，将 sqlplus 输出通过临时文件捕获，再用 `iconv -f GBK -t UTF-8` 转换后记录日志。

```bash
# 修复前：直接捕获输出（乱码）
output=$(sqlplus -s -L "$(connect_str "$user" "$pass")" @"$sql_file" 2>&1)

# 修复后：通过临时文件 + iconv 转换
sqlplus -s -L "$(connect_str "$user" "$pass")" @"$sql_file" > "$raw_output" 2>&1
iconv -f GBK -t UTF-8 "$raw_output" > "$utf8_output" 2>/dev/null
```

---

### 问题2：SQL 文件行数显示异常（48542 行显示为 0 行）

**现象**：日志显示"共 0 行"，但 SQL 文件实际有 48542 行数据。

**原因**：awk 内部的 `batch_count` 变量无法回传给 bash，导致 bash 侧始终为 0。

**解决方案**：改用 `wc -l` 统计 SQL 文件实际行数，不依赖 awk 内部变量。

```bash
# 修复后
total_lines=$(wc -l < "$sql_file")
```

---

### 问题3：SP2-0027 错误（输入太长 > 2499 字符）

**现象**：sqlplus 执行大 SQL 文件时报 `SP2-0027: Input is too long (> 2499 characters)` 错误。

**原因**：sqlplus 单行缓冲区限制为 2499 字节，字段多、中文占字节多时单条 INSERT 语句超限。

**解决方案**：

1. 在 SQL 文件开头增大缓冲区：
```sql
SET LINESIZE 32767
SET LONG 32767
```

2. 将单条 INSERT 语句拆成多行格式，每 10 个字段或每行超 400 字符时换行：
```sql
INSERT INTO TABLE (col1, col2, ..., col40)
VALUES (
    'val1', 'val2', ..., 'val10',
    'val11', 'val12', ..., 'val20',
    ...
);
```

---

### 问题4：CSV 中文未在 SQL 文件中正确生成

**现象**：CSV 文件中的中文（如"阳光个人消费贷"）在生成的 SQL 文件中变成乱码或部分字节丢失。

**原因**：awk 在默认 locale 下将 UTF-8 多字节中文字符拆开处理，导致字节丢失。

**解决方案**：在脚本启动时设置 UTF-8 locale，并自动检测可用的 locale 名称。

```bash
# 自动检测可用的 UTF-8 locale
for _loc in C.UTF-8 en_US.UTF-8 zh_CN.UTF-8 en_US.utf8 zh_CN.utf8 POSIX.UTF-8; do
    if locale -a 2>/dev/null | grep -qi "^${_loc}$"; then
        _UTF8_LOCALE="$_loc"
        break
    fi
done
export LC_ALL="$_UTF8_LOCALE"
```

---

### 问题5：iconv 转换静默丢弃字符

**现象**：SQL 文件编码转换时，部分无法映射的字符被静默丢弃，不报错。

**原因**：iconv 命令使用了 `-c` 参数（`--ignore-unmappable`），失败时不报错。

**解决方案**：去掉 `-c` 参数，转换失败时记录 `[ERROR]` 日志并提示检查 CSV 字符。

```bash
# 修复前（静默丢弃）
iconv -c -f UTF-8 -t GBK "$sql_file" > "$tmp_conv"

# 修复后（报错提示）
iconv -f UTF-8 -t GBK "$sql_file" > "$tmp_conv" 2>&1
if [ $? -ne 0 ]; then
    log_file "$file_log" "[ERROR] SQL 文件编码转换失败，请检查 CSV 文件是否包含无法转换的字符"
fi
```

---

### 问题6：INSERT 语句多行拆分后每行末尾缺少逗号

**现象**：INSERT 语句拆成多行后，每行末尾缺少逗号，导致 SQL 语法错误。

**原因**：原逻辑将逗号加在下一个值的开头（`val_line = val_line ", " pv`），换行时逗号跑到了下一行开头，上一行末尾无逗号。

**解决方案**：改为将逗号附在当前值后面，最后一个字段不加逗号。

```awk
# 修复前：逗号加在值前面
if (val_line == "") val_line = "    " pv
else val_line = val_line ", " pv

# 修复后：逗号加在值后面（最后一个字段不加）
if (k < FIELD_COUNT) pv = pv ", "
if (val_line == "") val_line = "    " pv
else val_line = val_line pv
```

---

### 问题7：Locale `C.UTF-8` 在目标服务器不存在

**现象**：脚本部署到目标服务器后，`export LC_ALL=C.UTF-8` 报错 `cannot set LC_ALL to locale`。

**原因**：不同 Linux 发行版安装的 locale 不同，`C.UTF-8` 不一定存在。

**解决方案**：改为自动检测可用的 UTF-8 locale，按优先级尝试多种名称，找不到时兜底设置 `LC_CTYPE`。

```bash
# 按优先级尝试：C.UTF-8 → en_US.UTF-8 → zh_CN.UTF-8 → ... → 任意含 utf-8 的
for _loc in C.UTF-8 en_US.UTF-8 zh_CN.UTF-8 en_US.utf8 zh_CN.utf8 POSIX.UTF-8; do
    if locale -a 2>/dev/null | grep -qi "^${_loc}$"; then
        export LC_ALL="$_loc"
        break
    fi
done
# 找不到精确匹配时，模糊查找
if [ -z "$LC_ALL" ]; then
    _UTF8_LOCALE=$(locale -a 2>/dev/null | grep -i 'utf.*8' | head -1)
    [ -n "$_UTF8_LOCALE" ] && export LC_ALL="$_UTF8_LOCALE"
fi
```

---

### 问题8：配置文件路径拼写错误

**现象**：`NLP_CSV_PATH` 路径中 `SH_ALL` 被误写为 `SH_ALl`（小写 l）。

**原因**：手动编辑配置文件时大小写输入错误。

**解决方案**：修正为 `SH_ALL`。

```ini
# 修复前
NLP_CSV_PATH=/home/nlp/SH_ALl/csv_nlp

# 修复后
NLP_CSV_PATH=/home/nlp/SH_ALL/csv_nlp
```

---

### 问题9：单文件处理串行执行效率低

**现象**：多个 CSV 文件逐个生成 SQL、逐个执行 sqlplus，处理时间长。

**原因**：步骤3（SQL 生成）和步骤4（SQL 执行）均为串行 `for` 循环，一个完成才处理下一个。

**解决方案**：新增 `MAX_PARALLEL` 配置项，两个阶段均支持并行处理：

- 每个任务在后台子shell中执行
- `wait_for_slot` 函数控制最大并发数
- 每个任务结果写入独立临时文件，避免变量竞争
- `MAX_PARALLEL=1` 时退化为串行（与原行为一致）

```bash
# 并发控制
wait_for_slot() {
    if [ "$MAX_PARALLEL" -le 1 ]; then return; fi
    while [ "$(jobs -rp | wc -l)" -ge "$MAX_PARALLEL" ]; do
        sleep 0.2
    done
}

# 后台执行 + 等待空位
( generate_sql_file ... > "$result_file" ) &
wait_for_slot
```
