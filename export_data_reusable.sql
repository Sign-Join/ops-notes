-- ================================================================
-- File    : export_data_reusable.sql  (v3.0-REUSABLE)
-- Purpose : Reusable DM (达梦) data exporter -> INSERT statements
--
--   Supported modes (edit CONFIG section, line ~37-58 only):
--     1) 全 schema 导出(仅含过滤列的表)   : v_table=NULL, v_filter_col='TENANT_ID',
--                                            v_filter_value='<值>'
--     2) 全 schema 全量导出(所有表)       : v_table=NULL, v_filter_col=NULL
--     3) 单表条件导出                     : v_table='ORG_UNIT', v_filter_col='TENANT_ID',
--                                            v_filter_value='<值>'
--     4) 单表全量导出                     : v_table='ORG_UNIT', v_filter_col=NULL
--                                            (或 v_filter_value=NULL)
--     5) 任意自定义 WHERE                 : v_custom_where='"tenant_id"=''xxx'' AND "status"=1'
--                                            (不带 WHERE 关键字, 优先级最高)
--
-- Engine  : DM 8.x (disql 03134284172 Pack4 verified)
-- Usage   : 交互式 disql 中执行:
--             SQL> START /home/app/export_tenant_data.sql
--           输出文件: 见下方 SPOOL 行(可改)
-- ================================================================

SET SERVEROUTPUT ON
SET LINESIZE 32767
SET PAGESIZE 0
SET FEEDBACK OFF
SET HEADING OFF
SET TRIMSPOOL ON
SET ECHO OFF
SET TIMING OFF

-- ====== SPOOL output file (修改输出文件路径时改这一行) ======
SPOOL /data/export_tenant_data.sql

PROMPT -- ============================================================
PROMPT -- DM Data Exporter (reusable v3.0)
PROMPT -- ============================================================
PROMPT

DECLARE
  -- ================================================================
  -- ====== CONFIG SECTION - 只改这里 ==============================
  -- ================================================================

  -- 目标 schema(owner)
  v_schema        VARCHAR2(128)  := 'ORGANIZATION';

  -- 目标表名。NULL = 导出整个 schema; 'XXX' = 只导出该表
  -- 注意: 单表模式不要求该表存在过滤列(不存在则全量导出并给 NOTE)
  v_table         VARCHAR2(128)  := NULL;

  -- 过滤列名(大小写不敏感匹配)。NULL = 不按列过滤
  v_filter_col    VARCHAR2(128)  := 'TENANT_ID';

  -- 过滤值。NULL = 不带条件(全量导出)。值内含单引号会自动转义
  v_filter_value  VARCHAR2(4000) := '-6532046674168823171';

  -- 'Y' = 过滤值加引号(字符串列); 'N' = 不加引号(数值列)
  v_filter_quote  VARCHAR2(1)    := 'Y';

  -- 自定义 WHERE(不含 WHERE 关键字), 优先级高于上面的 过滤列+过滤值。
  -- 注意: v_table=NULL(全 schema)模式下该条件会套用到每个表,
  --       必须保证每个被导出的表都有条件里引用的列, 否则该表会 SKIP。
  --       大小写敏感的列名需用双引号包裹(如 "tenant_id")。
  v_custom_where  VARCHAR2(4000) := NULL;
  
--例如:
--单个where条件：
---v_filter_col    VARCHAR2(128)  := 'IS_ENABLE';   -- 过滤列
---v_filter_value  VARCHAR2(4000) := '1';           -- 过滤值
---v_filter_quote  VARCHAR2(1)    := 'N';

---多个where条件:
---v_custom_where  VARCHAR2(4000) := '"id"=1111 AND "is_enable"=1';

  -- ================================================================
  -- End of CONFIG (以下勿动)
  -- ================================================================

  -- ====== Quote helpers ======
  v_q   VARCHAR2(1) := CHR(39);             -- single quote  : '
  v_2q  VARCHAR2(2) := CHR(39)||CHR(39);    -- two quotes    : ''  (one quote char in SQL string)
  v_dq  VARCHAR2(1) := CHR(34);             -- double quote  : "  (case-sensitive identifier)

  -- ====== Dynamic SQL and working variables ======
  v_sql        CLOB;
  v_col_list   VARCHAR2(32767);
  v_val_expr   CLOB;
  v_where      VARCHAR2(4000);
  v_rowcount   NUMBER;
  v_col_types  CLOB;              -- DIAG: accumulate column:type map per table
  v_col_cnt    NUMBER;            -- column counter for separator logic (DM: '' is NOT NULL!)
  v_tab_count  NUMBER := 0;       -- processed table counter (for "not found" warn)
BEGIN
  DBMS_OUTPUT.ENABLE(1000000);

  -- ---- dynamic header (mirrors actual config) ----
  DBMS_OUTPUT.PUT_LINE('-- Schema  : ' || v_schema);
  DBMS_OUTPUT.PUT_LINE('-- Table   : ' || NVL(v_table, '(ALL TABLES)'));
  IF v_custom_where IS NOT NULL THEN
    DBMS_OUTPUT.PUT_LINE('-- WHERE   : CUSTOM -> ' || v_custom_where);
  ELSIF v_filter_col IS NOT NULL AND v_filter_value IS NOT NULL THEN
    DBMS_OUTPUT.PUT_LINE('-- WHERE   : ' || v_filter_col || ' = ' || v_filter_value ||
                         CASE WHEN v_filter_quote='Y' THEN ' (quoted)' ELSE ' (raw)' END);
  ELSE
    DBMS_OUTPUT.PUT_LINE('-- WHERE   : (none - full export)');
  END IF;
  DBMS_OUTPUT.PUT_LINE('');

  -- ---- iterate target tables ----
  -- Unified cursor logic:
  --   * v_table set            -> that single table (filter col optional)
  --   * v_table NULL + col set -> all tables that HAVE the filter column
  --   * v_table NULL + no col  -> all tables in schema
  -- FILTER_COL holds the REAL column name (case preserved), NULL if absent.
  FOR tab IN (
    SELECT t.TABLE_NAME,
           c.COLUMN_NAME AS FILTER_COL
    FROM   ALL_TABLES t
    LEFT JOIN ALL_TAB_COLUMNS c
           ON c.OWNER = t.OWNER
          AND c.TABLE_NAME = t.TABLE_NAME
          AND UPPER(c.COLUMN_NAME) = UPPER(v_filter_col)
    WHERE  t.OWNER = v_schema
      AND  ( (v_table IS NOT NULL AND UPPER(t.TABLE_NAME) = UPPER(v_table))
             OR
             (v_table IS NULL AND v_filter_col IS NULL)
             OR
             (v_table IS NULL AND v_filter_col IS NOT NULL
              AND EXISTS (SELECT 1 FROM ALL_TAB_COLUMNS x
                          WHERE x.OWNER = t.OWNER AND x.TABLE_NAME = t.TABLE_NAME
                            AND UPPER(x.COLUMN_NAME) = UPPER(v_filter_col)))
           )
    ORDER BY t.TABLE_NAME
  ) LOOP

    v_tab_count := v_tab_count + 1;
    v_col_types := '';   -- DIAG: reset per table

    -- ---- build WHERE clause ----
    v_where := '';
    IF v_custom_where IS NOT NULL THEN
      v_where := ' WHERE ' || v_custom_where;
    ELSIF v_filter_col IS NOT NULL AND tab.FILTER_COL IS NOT NULL AND v_filter_value IS NOT NULL THEN
      IF v_filter_quote = 'Y' THEN
        v_where := ' WHERE "' || tab.FILTER_COL || '"=' || v_q ||
                   REPLACE(v_filter_value, v_q, v_2q) || v_q;
      ELSE
        v_where := ' WHERE "' || tab.FILTER_COL || '"=' || v_filter_value;
      END IF;
      -- single-table mode + filter col missing -> warn and export full table
    ELSIF v_table IS NOT NULL AND v_filter_col IS NOT NULL AND v_filter_value IS NOT NULL THEN
      DBMS_OUTPUT.PUT_LINE('-- NOTE: table ' || tab.TABLE_NAME ||
                           ' has no column ' || v_filter_col ||
                           '; exporting WITHOUT filter');
    END IF;

    -- ---- Check if this table has matching rows ----
    BEGIN
      EXECUTE IMMEDIATE
        'SELECT COUNT(*) FROM "' || v_schema || '"."' || tab.TABLE_NAME || '"' || v_where
        INTO v_rowcount;
    EXCEPTION
      WHEN OTHERS THEN
        v_rowcount := -1;
        DBMS_OUTPUT.PUT_LINE('-- SKIP ' || tab.TABLE_NAME || ': ' || SQLERRM);
    END;

    IF v_rowcount < 0 THEN
      CONTINUE;
    END IF;
    IF v_rowcount = 0 THEN
      DBMS_OUTPUT.PUT_LINE('-- SKIP ' || tab.TABLE_NAME || ' (0 matching rows)');
      CONTINUE;
    END IF;

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('-- Table: ' || tab.TABLE_NAME ||
                         '  (' || v_rowcount || ' rows)');

    -- ---- Build column list and value expression ----
    v_col_list := '';
    v_val_expr := '';
    v_col_cnt  := 0;   -- MUST use a counter: in DM, '' is an empty string, NOT NULL,
                       -- so "IS NOT NULL" is TRUE on the very first column and would
                       -- prepend a separator -> broken column list and "Operator is not found".

    FOR col IN (
      SELECT COLUMN_NAME, DATA_TYPE
      FROM   ALL_TAB_COLUMNS
      WHERE  OWNER      = v_schema
        AND  TABLE_NAME = tab.TABLE_NAME
      ORDER BY COLUMN_ID
    ) LOOP

      -- Column separator (only after the first column)
      IF v_col_cnt > 0 THEN
        v_col_list := v_col_list || ',';
        v_val_expr := v_val_expr || '||' || v_q || ',' || v_q || '||';
      END IF;
      v_col_cnt := v_col_cnt + 1;

      -- Column name wrapped in double quotes (handles lowercase column names)
      v_col_list := v_col_list || v_dq || col.COLUMN_NAME || v_dq;
      v_col_types := v_col_types || col.COLUMN_NAME || '=' || col.DATA_TYPE || '; ';  -- DIAG

      -- ---- Value expression by data type ----
      IF col.DATA_TYPE IN ('BIT','BOOLEAN') THEN
        -- BIT/BOOLEAN: DM has NO TO_CHAR(bit) operator -> guard separately,
        -- output 1/0 as plain text (is_deleted-style marker columns).
        v_val_expr := v_val_expr ||
          'CASE WHEN ' || v_dq || col.COLUMN_NAME || v_dq || ' IS NULL THEN ' ||
          v_q || 'NULL' || v_q ||
          ' ELSE CASE WHEN ' || v_dq || col.COLUMN_NAME || v_dq || '=1 THEN ' ||
          v_q || '1' || v_q ||
          ' ELSE ' || v_q || '0' || v_q || ' END END';

      ELSIF col.DATA_TYPE IN (
        'NUMBER','INT','INTEGER','BIGINT','TINYINT','SMALLINT',
        'DECIMAL','FLOAT','DOUBLE','NUMERIC','REAL'
      ) THEN
        -- Numeric types: no quotes, NULL for nulls
        v_val_expr := v_val_expr ||
          'CASE WHEN ' || v_dq || col.COLUMN_NAME || v_dq || ' IS NULL THEN ' ||
          v_q || 'NULL' || v_q ||
          ' ELSE TO_CHAR(' || v_dq || col.COLUMN_NAME || v_dq || ') END';

      ELSIF col.DATA_TYPE IN (
        'BLOB','BINARY','VARBINARY','IMAGE','LONGVARBINARY',
        'CLOB','NCLOB','TEXT','LONG','LONGVARCHAR'
      ) THEN
        -- LOB/large types: output NULL (cannot safely inline into INSERT text)
        v_val_expr := v_val_expr || v_q || 'NULL' || v_q;
        DBMS_OUTPUT.PUT_LINE('--   NOTE: ' || col.DATA_TYPE || ' column ' || col.COLUMN_NAME || ' exported as NULL');

      ELSE
        -- String / Date / other types: TO_CHAR first, then quote-escape.
        -- DM raises "Operator is not found" when REPLACE() is called directly on
        -- DATE/TIMESTAMP columns, so TO_CHAR() must wrap the column.
        -- Produces: CASE WHEN "col" IS NULL THEN 'NULL'
        --               ELSE ''''||REPLACE(TO_CHAR("col"),'''','''''')||'''' END
        -- A = open quote (1 quote char)  -> v_2q||v_2q             (2)
        -- B = search one quote           -> v_2q||v_2q             (2)
        -- C = replace with two quotes    -> v_2q||v_2q||v_2q       (3)
        -- D = close quote (1 quote char) -> v_2q||v_2q             (2)
        v_val_expr := v_val_expr ||
          'CASE WHEN ' || v_dq || col.COLUMN_NAME || v_dq || ' IS NULL THEN ' ||
          v_q || 'NULL' || v_q || ' ELSE ' ||
          v_2q || v_2q ||                                  -- A
          '||REPLACE(TO_CHAR(' || v_dq || col.COLUMN_NAME || v_dq || '),' ||
          v_2q || v_2q ||                                  -- B
          ',' ||
          v_2q || v_2q || v_2q ||                          -- C
          ')||' || v_2q || v_2q ||                         -- D
          ' END';

      END IF;

    END LOOP;

    -- Skip if no columns found
    IF v_col_cnt = 0 THEN
      CONTINUE;
    END IF;

    -- ---- Build the full dynamic SQL ----
    v_sql := 'SELECT ' || v_q ||
             'INSERT INTO "' || v_schema || '"."' || tab.TABLE_NAME || '"' ||
             '(' || v_col_list || ') VALUES (' || v_q ||
             '||' || v_val_expr ||
             '||' || v_q || ');' || v_q ||
             ' FROM "' || v_schema || '"."' || tab.TABLE_NAME || '"' || v_where;

    -- ---- Execute dynamic SQL and output each generated INSERT line ----
    BEGIN
      DECLARE
        rc     SYS_REFCURSOR;
        v_line VARCHAR2(32767);
      BEGIN
        OPEN rc FOR v_sql;
        LOOP
          FETCH rc INTO v_line;
          EXIT WHEN rc%NOTFOUND;
          DBMS_OUTPUT.PUT_LINE(v_line);
        END LOOP;
        CLOSE rc;
      EXCEPTION
        WHEN OTHERS THEN
          DBMS_OUTPUT.PUT_LINE('-- ERROR on ' || tab.TABLE_NAME || ': ' || SQLERRM);
          -- DIAG: dump column type map + the exact generated SQL for inspection
          DBMS_OUTPUT.PUT_LINE('--   cols: ' || v_col_types);
          DBMS_OUTPUT.PUT_LINE('-- >>> SQL START >>>');
          DECLARE
            v_pos  NUMBER := 1;
            v_len  NUMBER := LENGTH(v_sql);
          BEGIN
            WHILE v_pos <= v_len LOOP
              DBMS_OUTPUT.PUT_LINE(SUBSTR(v_sql, v_pos, 1000));
              v_pos := v_pos + 1000;
            END LOOP;
          END;
          DBMS_OUTPUT.PUT_LINE('-- >>> SQL END >>>');
      END;
    END;

  END LOOP;

  -- ---- single-table mode: table not found warning ----
  IF v_table IS NOT NULL AND v_tab_count = 0 THEN
    DBMS_OUTPUT.PUT_LINE('-- WARNING: table ' || v_table || ' not found in schema ' || v_schema);
  END IF;

  DBMS_OUTPUT.PUT_LINE('');
  DBMS_OUTPUT.PUT_LINE('-- ============================================================');
  DBMS_OUTPUT.PUT_LINE('-- Export complete (' || v_tab_count || ' table(s) processed)');
  DBMS_OUTPUT.PUT_LINE('-- ============================================================');

END;
/

SPOOL OFF
EXIT
