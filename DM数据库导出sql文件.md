# DM数据库导出sql文件

[export\_data\_reusable\.sql](图片和附件/export_data_reusable.sql)

```plain
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
--		例如:
--		单个where条件：
--		v_filter_col    VARCHAR2(128)  := 'IS_ENABLE';   -- 过滤列
--		v_filter_value  VARCHAR2(4000) := '1';           -- 过滤值
--		v_filter_quote  VARCHAR2(1)    := 'N';

--		多个where条件:
--		v_custom_where  VARCHAR2(4000) := '"id"=1111 AND "is_enable"=1';
--
-- Engine  : DM 8.x (disql 03134284172 Pack4 verified)
-- Usage   : 交互式 disql 中执行:
--             SQL> START /home/app/export_tenant_data.sql
--           输出文件: 见脚本 SPOOL 行(可改)
```

