--
-- PostgreSQL database dump
--

-- Dumped from database version 16.4
-- Dumped by pg_dump version 16.4

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: partition_admin; Type: SCHEMA; Schema: -; Owner: gtmsmanager
--

CREATE SCHEMA partition_admin;


ALTER SCHEMA partition_admin OWNER TO gtmsmanager;

--
-- Name: boolean_to_numeric(boolean); Type: FUNCTION; Schema: public; Owner: gtmsmanager
--

CREATE FUNCTION public.boolean_to_numeric(b boolean) RETURNS numeric
    LANGUAGE plpgsql
    AS $$
 BEGIN
 RETURN (b::boolean)::bool::int;
 END;
$$;


ALTER FUNCTION public.boolean_to_numeric(b boolean) OWNER TO gtmsmanager;

--
-- Name: CAST (boolean AS numeric); Type: CAST; Schema: -; Owner: -
--

CREATE CAST (boolean AS numeric) WITH FUNCTION public.boolean_to_numeric(boolean) AS IMPLICIT;


--
-- Name: CAST (character AS numeric); Type: CAST; Schema: -; Owner: -
--

CREATE CAST (character AS numeric) WITH INOUT AS IMPLICIT;


--
-- Name: CAST (numeric AS character varying); Type: CAST; Schema: -; Owner: -
--

CREATE CAST (numeric AS character varying) WITH INOUT AS IMPLICIT;


--
-- Name: CAST (text AS numeric); Type: CAST; Schema: -; Owner: -
--

CREATE CAST (text AS numeric) WITH INOUT AS IMPLICIT;


--
-- Name: CAST (character varying AS integer); Type: CAST; Schema: -; Owner: -
--

CREATE CAST (character varying AS integer) WITH INOUT AS IMPLICIT;


--
-- Name: CAST (character varying AS numeric); Type: CAST; Schema: -; Owner: -
--

CREATE CAST (character varying AS numeric) WITH INOUT AS IMPLICIT;


--
-- Name: drop_expired_daily_partitions(text, text, integer); Type: FUNCTION; Schema: partition_admin; Owner: gtmsmanager
--

CREATE FUNCTION partition_admin.drop_expired_daily_partitions(p_schema_name text, p_table_name text, p_keep_days integer) RETURNS void
    LANGUAGE plpgsql
    AS $_$
DECLARE
    v_rel record;
    v_suffix text;
    v_partition_day date;
    v_drop_before date;
BEGIN
    v_drop_before := current_date - p_keep_days;

    FOR v_rel IN
        SELECT c.relname AS partition_name
        FROM pg_inherits i
        JOIN pg_class c ON c.oid = i.inhrelid
        JOIN pg_class p ON p.oid = i.inhparent
        JOIN pg_namespace n ON n.oid = p.relnamespace
        WHERE n.nspname = p_schema_name
          AND p.relname = p_table_name
    LOOP
        v_suffix := substring(v_rel.partition_name FROM 'p([0-9]{8})$');

        IF v_suffix IS NULL THEN
            CONTINUE;
        END IF;

        v_partition_day := to_date(v_suffix, 'YYYYMMDD');

        IF v_partition_day < v_drop_before THEN
            EXECUTE format('DROP TABLE IF EXISTS %I.%I', p_schema_name, v_rel.partition_name);
        END IF;
    END LOOP;
END;
$_$;


ALTER FUNCTION partition_admin.drop_expired_daily_partitions(p_schema_name text, p_table_name text, p_keep_days integer) OWNER TO gtmsmanager;

--
-- Name: ensure_daily_partition(text, text, text, date); Type: FUNCTION; Schema: partition_admin; Owner: gtmsmanager
--

CREATE FUNCTION partition_admin.ensure_daily_partition(p_schema_name text, p_table_name text, p_owner_name text, p_day date) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_partition_name text;
    v_partition_fq_name text;
    v_start_ts bigint;
    v_end_ts bigint;
BEGIN
    v_partition_name := partition_admin.partition_name(p_table_name, p_day);
    v_partition_fq_name := format('%I.%I', p_schema_name, v_partition_name);

    IF to_regclass(v_partition_fq_name) IS NOT NULL THEN
        RETURN;
    END IF;

    v_start_ts := extract(epoch FROM p_day)::bigint;
    v_end_ts := extract(epoch FROM (p_day + 1))::bigint;

    EXECUTE format(
        'CREATE TABLE %I.%I PARTITION OF %I.%I FOR VALUES FROM (%s) TO (%s)',
        p_schema_name, v_partition_name, p_schema_name, p_table_name, v_start_ts, v_end_ts
    );

    EXECUTE format('ALTER TABLE %I.%I OWNER TO %I', p_schema_name, v_partition_name, p_owner_name);
END;
$$;


ALTER FUNCTION partition_admin.ensure_daily_partition(p_schema_name text, p_table_name text, p_owner_name text, p_day date) OWNER TO gtmsmanager;

--
-- Name: maintain_daily_partitions(); Type: FUNCTION; Schema: partition_admin; Owner: gtmsmanager
--

CREATE FUNCTION partition_admin.maintain_daily_partitions() RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_cfg record;
    v_day date;
BEGIN
    FOR v_cfg IN
        SELECT table_name, keep_days, precreate_days, owner_name
        FROM partition_admin.partition_config
    LOOP
        FOR v_day IN
            SELECT generate_series(current_date - 1, current_date + v_cfg.precreate_days, interval '1 day')::date
        LOOP
            PERFORM partition_admin.ensure_daily_partition('public', v_cfg.table_name, v_cfg.owner_name, v_day);
        END LOOP;

        PERFORM partition_admin.drop_expired_daily_partitions('public', v_cfg.table_name, v_cfg.keep_days);
    END LOOP;
END;
$$;


ALTER FUNCTION partition_admin.maintain_daily_partitions() OWNER TO gtmsmanager;

--
-- Name: partition_name(text, date); Type: FUNCTION; Schema: partition_admin; Owner: gtmsmanager
--

CREATE FUNCTION partition_admin.partition_name(p_table_name text, p_day date) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
    SELECT format('%s_p%s', p_table_name, to_char(p_day, 'YYYYMMDD'));
$$;


ALTER FUNCTION partition_admin.partition_name(p_table_name text, p_day date) OWNER TO gtmsmanager;

--
-- Name: maxresid(integer, integer, bigint); Type: PROCEDURE; Schema: public; Owner: gtmsmanager
--

CREATE PROCEDURE public.maxresid(IN res_type integer, IN counts integer, INOUT maxid bigint)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_count integer;
BEGIN
    -- 初始化变量
    v_count := 0;

    -- 使用动态SQL获取计数
    EXECUTE format('SELECT COUNT(*) FROM tab_gw_identity WHERE res_type = %L', res_type) INTO v_count;

    IF v_count = 0 THEN
        -- 开始一个新的事务（在本例中可能不是必须的，因为每次操作后都会提交）
        -- BEGIN;

        -- 插入新记录
        EXECUTE format('INSERT INTO tab_gw_identity(res_type, maxid) VALUES (%L, %L)', res_type, counts);

        -- 提交事务
        COMMIT;

        -- 计算并设置maxId
        EXECUTE format('SELECT maxid - %L + 1 FROM tab_gw_identity WHERE res_type = %L', counts, res_type) INTO maxId;
    ELSE
        -- 开始一个新的事务（同上）
        -- BEGIN;

        -- 更新记录
        EXECUTE format('UPDATE tab_gw_identity SET maxid = maxid + %L WHERE res_type = %L', counts, res_type);



        -- 计算并设置maxId
        EXECUTE format('SELECT maxid - %L + 1 FROM tab_gw_identity WHERE res_type = %L', counts, res_type) INTO maxId;
         -- 提交事务
        COMMIT;
    END IF;

    -- 在某些情况下，可能还需要最终的提交，取决于外部事务的管理
    -- COMMIT;
END;
$$;


ALTER PROCEDURE public.maxresid(IN res_type integer, IN counts integer, INOUT maxid bigint) OWNER TO gtmsmanager;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: partition_config; Type: TABLE; Schema: partition_admin; Owner: gtmsmanager
--

CREATE TABLE partition_admin.partition_config (
    table_name text NOT NULL,
    keep_days integer NOT NULL,
    precreate_days integer NOT NULL,
    owner_name text DEFAULT 'gtmsmanager'::text NOT NULL
);


ALTER TABLE partition_admin.partition_config OWNER TO gtmsmanager;

--
-- Name: bind_log; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.bind_log (
    bind_id numeric(15,0) NOT NULL,
    username character varying(40) NOT NULL,
    credno character varying(20),
    device_id character varying(50) NOT NULL,
    binddate numeric(10,0) NOT NULL,
    bind_status numeric(2,0),
    bind_result numeric(2,0) NOT NULL,
    bind_desc character varying(50),
    userline numeric(6,0) NOT NULL,
    remark character varying(100),
    oper_type numeric(1,0),
    bind_type numeric(1,0),
    dealstaff character varying(80) NOT NULL
);


ALTER TABLE public.bind_log OWNER TO gtmsmanager;

--
-- Name: COLUMN bind_log.username; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.bind_log.username IS '用户帐号
无线卡号';


--
-- Name: COLUMN bind_log.binddate; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.bind_log.binddate IS '秒';


--
-- Name: COLUMN bind_log.bind_status; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.bind_log.bind_status IS 'bind_status(bind_status) ';


--
-- Name: COLUMN bind_log.bind_result; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.bind_log.bind_result IS '99：无业务下发（默认）
0:开始下发业务
1：成功
2：失败';


--
-- Name: COLUMN bind_log.userline; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.bind_log.userline IS '0 IPOSS绑定
1 手工绑定
2 自助绑定
3 设备物理SN自动绑定
4 MAC绑定
5 桥接账号自动绑定
6 设备逻辑SN自动绑定  ';


--
-- Name: COLUMN bind_log.oper_type; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.bind_log.oper_type IS '1:绑定
2:解绑
3:修障
';


--
-- Name: COLUMN bind_log.bind_type; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.bind_log.bind_type IS '1：用户绑定设备
2：无线卡绑定设备';


--
-- Name: bind_log_tapdata_id_seq; Type: SEQUENCE; Schema: public; Owner: gtmsmanager
--

CREATE SEQUENCE public.bind_log_tapdata_id_seq
    START WITH 808
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 2147483647
    CACHE 1;


ALTER SEQUENCE public.bind_log_tapdata_id_seq OWNER TO gtmsmanager;

--
-- Name: bind_type; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.bind_type (
    bind_type_id numeric(2,0) NOT NULL,
    type_name character varying(30) NOT NULL,
    remark character varying(50)
);


ALTER TABLE public.bind_type OWNER TO gtmsmanager;

--
-- Name: bridge_route_oper_log; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.bridge_route_oper_log (
    oper_action character varying(1),
    oper_result character varying(1),
    loid character varying(64),
    username character varying(80),
    oper_origon character varying(30),
    oper_staff character varying(20),
    add_time numeric(10,0),
    result_desc character varying(200)
);


ALTER TABLE public.bridge_route_oper_log OWNER TO gtmsmanager;

--
-- Name: capacity_log_sequence; Type: SEQUENCE; Schema: public; Owner: gtmsmanager
--

CREATE SEQUENCE public.capacity_log_sequence
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.capacity_log_sequence OWNER TO gtmsmanager;

--
-- Name: cpe_gather_config; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.cpe_gather_config (
    id numeric(10,0) NOT NULL,
    city_id character varying(20) NOT NULL,
    g_interval numeric(10,0)
);


ALTER TABLE public.cpe_gather_config OWNER TO gtmsmanager;

--
-- Name: COLUMN cpe_gather_config.id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.cpe_gather_config.id IS '大业务ID，比如2代表采集整个WANDevice';


--
-- Name: cpe_gather_node_tabname; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.cpe_gather_node_tabname (
    id integer NOT NULL,
    tab_name character varying(200) NOT NULL,
    tab_column_name character varying(200) NOT NULL,
    cpe_node_name text NOT NULL,
    has_i numeric(1,0) NOT NULL
);


ALTER TABLE public.cpe_gather_node_tabname OWNER TO gtmsmanager;

--
-- Name: TABLE cpe_gather_node_tabname; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON TABLE public.cpe_gather_node_tabname IS 'TR069采集_设备节点表名对应表';


--
-- Name: cpe_gather_node_tabname_tapdata_id_seq; Type: SEQUENCE; Schema: public; Owner: gtmsmanager
--

CREATE SEQUENCE public.cpe_gather_node_tabname_tapdata_id_seq
    START WITH 4394
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 2147483647
    CACHE 1;


ALTER SEQUENCE public.cpe_gather_node_tabname_tapdata_id_seq OWNER TO gtmsmanager;

--
-- Name: cpe_gather_param_type; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.cpe_gather_param_type (
    id numeric(10,0) NOT NULL,
    node_name character varying(200) NOT NULL,
    node_path character varying(200) NOT NULL,
    need_gather numeric(1,0) NOT NULL,
    remark character varying(200)
);


ALTER TABLE public.cpe_gather_param_type OWNER TO gtmsmanager;

--
-- Name: cpe_gather_param_type_bbms; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.cpe_gather_param_type_bbms (
    id numeric(6,0) NOT NULL,
    node_name character varying(100) NOT NULL,
    node_path character varying(200) NOT NULL,
    need_gather numeric(1,0) NOT NULL,
    remark character varying(200)
);


ALTER TABLE public.cpe_gather_param_type_bbms OWNER TO gtmsmanager;

--
-- Name: cpe_gather_param_type_bbms_tapdata_id_seq; Type: SEQUENCE; Schema: public; Owner: gtmsmanager
--

CREATE SEQUENCE public.cpe_gather_param_type_bbms_tapdata_id_seq
    START WITH 190
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 2147483647
    CACHE 1;


ALTER SEQUENCE public.cpe_gather_param_type_bbms_tapdata_id_seq OWNER TO gtmsmanager;

--
-- Name: cpe_gather_param_type_tapdata_id_seq; Type: SEQUENCE; Schema: public; Owner: gtmsmanager
--

CREATE SEQUENCE public.cpe_gather_param_type_tapdata_id_seq
    START WITH 112
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 2147483647
    CACHE 1;


ALTER SEQUENCE public.cpe_gather_param_type_tapdata_id_seq OWNER TO gtmsmanager;

--
-- Name: cpe_gather_record; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.cpe_gather_record (
    device_id character varying(50) NOT NULL,
    param_type numeric(10,0) NOT NULL,
    start_time numeric(10,0),
    end_time numeric(10,0),
    is_succ numeric(10,0),
    failure_reason character varying(255)
);


ALTER TABLE public.cpe_gather_record OWNER TO gtmsmanager;

--
-- Name: COLUMN cpe_gather_record.param_type; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.cpe_gather_record.param_type IS '0：采集配置文件中所有参数
1：LANDevice
2：WANDevice
3：
X_CT-COM_UplinkQoS
4：
X_ATP_Security
5：Services
';


--
-- Name: COLUMN cpe_gather_record.is_succ; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.cpe_gather_record.is_succ IS '1：成功
0：失败
';


--
-- Name: cpe_gather_result; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.cpe_gather_result (
    device_id character varying(20) NOT NULL,
    gather_time numeric(10,0) NOT NULL,
    id numeric(10,0) NOT NULL,
    service_result numeric(1,0) NOT NULL,
    service_desc character varying(100)
);


ALTER TABLE public.cpe_gather_result OWNER TO gtmsmanager;

--
-- Name: COLUMN cpe_gather_result.id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.cpe_gather_result.id IS 'cpe_gather_param_type中的id';


--
-- Name: COLUMN cpe_gather_result.service_result; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.cpe_gather_result.service_result IS '0:未开通
1:开通';


--
-- Name: dev_event_type; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.dev_event_type (
    event_id numeric(2,0) NOT NULL,
    event_name character varying(50) NOT NULL
);


ALTER TABLE public.dev_event_type OWNER TO gtmsmanager;

--
-- Name: dev_event_type_tapdata_id_seq; Type: SEQUENCE; Schema: public; Owner: gtmsmanager
--

CREATE SEQUENCE public.dev_event_type_tapdata_id_seq
    START WITH 310
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 2147483647
    CACHE 1;


ALTER SEQUENCE public.dev_event_type_tapdata_id_seq OWNER TO gtmsmanager;

--
-- Name: egw_item_role; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.egw_item_role (
    sequence numeric(6,0),
    item_id character varying(36) NOT NULL,
    role_id numeric(3,0) NOT NULL
);


ALTER TABLE public.egw_item_role OWNER TO gtmsmanager;

--
-- Name: egwcust_serv_info; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.egwcust_serv_info (
    user_id numeric(10,0) NOT NULL,
    serv_type_id numeric(4,0) NOT NULL,
    username character varying(40),
    orderid character varying(50),
    serv_status numeric(1,0) NOT NULL,
    passwd character varying(40),
    wan_type numeric(2,0) NOT NULL,
    vpiid character varying(50),
    vciid numeric(6,0),
    vlanid character varying(50),
    ipaddress character varying(15),
    ipmask character varying(15),
    gateway character varying(15),
    adsl_ser character varying(30),
    bind_port text,
    wan_value_1 character varying(200) NOT NULL,
    wan_value_2 character varying(200) NOT NULL,
    open_status numeric(1,0) NOT NULL,
    dealdate numeric(10,0),
    opendate numeric(10,0),
    pausedate numeric(10,0),
    closedate numeric(10,0),
    updatetime numeric(10,0),
    completedate numeric(10,0),
    serv_num numeric(3,0),
    multicast_vlanid character varying(20)
);


ALTER TABLE public.egwcust_serv_info OWNER TO gtmsmanager;

--
-- Name: COLUMN egwcust_serv_info.serv_status; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.egwcust_serv_info.serv_status IS '1:����
2:����
3:����';


--
-- Name: COLUMN egwcust_serv_info.wan_type; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.egwcust_serv_info.wan_type IS '1:PPPoE(����)
2:PPPoE(����)
3:STATIC
4:DHCP';


--
-- Name: COLUMN egwcust_serv_info.bind_port; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.egwcust_serv_info.bind_port IS '����������������
LAN1
LAN2
LAN3
LAN4
WLAN1
WLAN2
WLAN3
WLAN4';


--
-- Name: COLUMN egwcust_serv_info.open_status; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.egwcust_serv_info.open_status IS '0������
1������
-1:����';


--
-- Name: en_sys_permission; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.en_sys_permission (
    id character varying(32) NOT NULL,
    parent_id character varying(32),
    name character varying(100),
    url character varying(255),
    component character varying(255),
    component_name character varying(100),
    redirect character varying(255),
    menu_type numeric(11,0),
    perms character varying(255),
    perms_type character varying(10),
    sort_no numeric(8,2),
    always_show numeric(4,0),
    icon character varying(100),
    is_route numeric(4,0),
    is_leaf numeric(4,0),
    keep_alive numeric(4,0),
    hidden numeric(11,0),
    hide_tab numeric(11,0),
    description character varying(255),
    create_by character varying(32),
    create_time timestamp without time zone,
    update_by character varying(32),
    update_time timestamp without time zone,
    del_flag numeric(11,0),
    rule_flag numeric(11,0),
    status character varying(2),
    internal_or_external numeric(4,0)
);


ALTER TABLE public.en_sys_permission OWNER TO gtmsmanager;

--
-- Name: guangkuan_reboot_info; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.guangkuan_reboot_info (
    device_id character varying(100) NOT NULL,
    cpuusage character varying(10),
    memusage character varying(10),
    sysduration character varying(10),
    temperature character varying(20),
    loadtime character varying(10),
    speed character varying(10),
    status character varying(10),
    getinfodate numeric(20,0) NOT NULL,
    reboot_reason character varying(20),
    reboot_time numeric(20,0),
    cpuusage_new character varying(10),
    memusage_new character varying(10),
    sysduration_new character varying(10),
    temperature_new character varying(20),
    loadtime_new character varying(10),
    speed_new character varying(10),
    isupdate character varying(10),
    isimprove character varying(10)
);


ALTER TABLE public.guangkuan_reboot_info OWNER TO gtmsmanager;

--
-- Name: COLUMN guangkuan_reboot_info.cpuusage; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.guangkuan_reboot_info.cpuusage IS 'CPU';


--
-- Name: COLUMN guangkuan_reboot_info.memusage; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.guangkuan_reboot_info.memusage IS '内存';


--
-- Name: COLUMN guangkuan_reboot_info.sysduration; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.guangkuan_reboot_info.sysduration IS '在线时长';


--
-- Name: COLUMN guangkuan_reboot_info.temperature; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.guangkuan_reboot_info.temperature IS '温度';


--
-- Name: COLUMN guangkuan_reboot_info.loadtime; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.guangkuan_reboot_info.loadtime IS '首页加载时长';


--
-- Name: COLUMN guangkuan_reboot_info.speed; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.guangkuan_reboot_info.speed IS '首页下载速率';


--
-- Name: COLUMN guangkuan_reboot_info.status; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.guangkuan_reboot_info.status IS '重启状态（1:重启成功;-1:重启失败;0:未重启 2：不需要重启）';


--
-- Name: COLUMN guangkuan_reboot_info.getinfodate; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.guangkuan_reboot_info.getinfodate IS '采集时间(采集指标的前值)';


--
-- Name: COLUMN guangkuan_reboot_info.reboot_reason; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.guangkuan_reboot_info.reboot_reason IS '重启原因';


--
-- Name: COLUMN guangkuan_reboot_info.reboot_time; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.guangkuan_reboot_info.reboot_time IS '重启时间';


--
-- Name: COLUMN guangkuan_reboot_info.cpuusage_new; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.guangkuan_reboot_info.cpuusage_new IS 'CPU_后值';


--
-- Name: COLUMN guangkuan_reboot_info.memusage_new; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.guangkuan_reboot_info.memusage_new IS '内存_后值';


--
-- Name: COLUMN guangkuan_reboot_info.sysduration_new; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.guangkuan_reboot_info.sysduration_new IS '在线时长_后值';


--
-- Name: COLUMN guangkuan_reboot_info.temperature_new; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.guangkuan_reboot_info.temperature_new IS '温度_后值';


--
-- Name: COLUMN guangkuan_reboot_info.loadtime_new; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.guangkuan_reboot_info.loadtime_new IS '首页加载时长_后值';


--
-- Name: COLUMN guangkuan_reboot_info.speed_new; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.guangkuan_reboot_info.speed_new IS '首页下载速率_后值';


--
-- Name: COLUMN guangkuan_reboot_info.isupdate; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.guangkuan_reboot_info.isupdate IS '是否已经获取了重启后的指标数据 0:未获取 1：已获取';


--
-- Name: COLUMN guangkuan_reboot_info.isimprove; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.guangkuan_reboot_info.isimprove IS '是否改善 0:未改善 1：已改善';


--
-- Name: gw_access_type; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_access_type (
    type_id numeric(2,0) NOT NULL,
    type_name character varying(50) NOT NULL,
    type_desc character varying(100)
);


ALTER TABLE public.gw_access_type OWNER TO gtmsmanager;

--
-- Name: gw_access_type_tapdata_id_seq; Type: SEQUENCE; Schema: public; Owner: gtmsmanager
--

CREATE SEQUENCE public.gw_access_type_tapdata_id_seq
    START WITH 16
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 2147483647
    CACHE 1;


ALTER SEQUENCE public.gw_access_type_tapdata_id_seq OWNER TO gtmsmanager;

--
-- Name: gw_acs_stream; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_acs_stream (
    stream_id numeric(10,0) NOT NULL,
    device_id character varying(10) NOT NULL,
    device_ip character varying(30) NOT NULL,
    toward numeric(1,0) NOT NULL,
    inter_time numeric(13,0) NOT NULL,
    s_ip character varying(30),
    s_port numeric(10,0),
    d_ip character varying(30),
    d_port numeric(10,0),
    inter_content text
);


ALTER TABLE public.gw_acs_stream OWNER TO gtmsmanager;

--
-- Name: COLUMN gw_acs_stream.toward; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_acs_stream.toward IS '1:ACS????????
2:????????ACS';


--
-- Name: COLUMN gw_acs_stream.inter_time; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_acs_stream.inter_time IS 'unit:ms';


--
-- Name: gw_acs_stream_content; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_acs_stream_content (
    stream_id numeric(10,0) NOT NULL,
    order_id numeric(10,0) NOT NULL,
    device_id character varying(10) NOT NULL,
    inter_content text
);


ALTER TABLE public.gw_acs_stream_content OWNER TO gtmsmanager;

--
-- Name: gw_acs_stream_tapdata_id_seq; Type: SEQUENCE; Schema: public; Owner: gtmsmanager
--

CREATE SEQUENCE public.gw_acs_stream_tapdata_id_seq
    START WITH 496578
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 2147483647
    CACHE 1;


ALTER SEQUENCE public.gw_acs_stream_tapdata_id_seq OWNER TO gtmsmanager;

--
-- Name: gw_alg; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_alg (
    device_id character varying(50) NOT NULL,
    gather_time numeric(10,0),
    h323_enab numeric(1,0),
    sip_enab numeric(1,0),
    rtsp_enab numeric(1,0),
    l2tp_enab numeric(1,0),
    ipsec_enab numeric(1,0)
);


ALTER TABLE public.gw_alg OWNER TO gtmsmanager;

--
-- Name: gw_alg_bbms; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_alg_bbms (
    device_id character varying(50) NOT NULL,
    gather_time numeric(10,0),
    h323_enab numeric(1,0),
    sip_enab numeric(1,0),
    rtsp_enab numeric(1,0),
    l2tp_enab numeric(1,0),
    ipsec_enab numeric(1,0)
);


ALTER TABLE public.gw_alg_bbms OWNER TO gtmsmanager;

--
-- Name: gw_card_manage; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_card_manage (
    device_id character varying(10) NOT NULL,
    gather_time numeric(10,0),
    card_no character varying(64) NOT NULL,
    status numeric(1,0) NOT NULL,
    card_status numeric(1,0) NOT NULL
);


ALTER TABLE public.gw_card_manage OWNER TO gtmsmanager;

--
-- Name: gw_conf_template; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_conf_template (
    temp_id numeric(4,0) NOT NULL,
    temp_name character varying(30) NOT NULL,
    type_desc character varying(100)
);


ALTER TABLE public.gw_conf_template OWNER TO gtmsmanager;

--
-- Name: gw_conf_template_service; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_conf_template_service (
    temp_id numeric(4,0) NOT NULL,
    order_id numeric(4,0) NOT NULL,
    serv_type_id numeric(4,0) NOT NULL,
    oper_type_id numeric(4,0) NOT NULL
);


ALTER TABLE public.gw_conf_template_service OWNER TO gtmsmanager;

--
-- Name: gw_cust_user_dev_type; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_cust_user_dev_type (
    customer_id character varying(100) NOT NULL,
    user_id numeric(10,0) NOT NULL,
    type_id character varying(10) NOT NULL,
    "time" numeric(10,0) NOT NULL
);


ALTER TABLE public.gw_cust_user_dev_type OWNER TO gtmsmanager;

--
-- Name: gw_cust_user_package; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_cust_user_package (
    customer_id character varying(100) NOT NULL,
    user_id numeric(10,0) NOT NULL,
    serv_package_id character varying(10) NOT NULL,
    "time" numeric(10,0)
);


ALTER TABLE public.gw_cust_user_package OWNER TO gtmsmanager;

--
-- Name: gw_cust_user_package_copy1; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_cust_user_package_copy1 (
    customer_id character varying(100) NOT NULL,
    user_id numeric(10,0) NOT NULL,
    serv_package_id character varying(10) NOT NULL,
    "time" numeric(10,0)
);


ALTER TABLE public.gw_cust_user_package_copy1 OWNER TO gtmsmanager;

--
-- Name: gw_dev_model_dev_type; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_dev_model_dev_type (
    device_model_id character varying(4) NOT NULL,
    type_id character varying(10) NOT NULL
);


ALTER TABLE public.gw_dev_model_dev_type OWNER TO gtmsmanager;

--
-- Name: gw_dev_serv; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_dev_serv (
    device_id character varying(10) NOT NULL,
    serv_type_id numeric(4,0) NOT NULL,
    serv_state numeric(1,0) NOT NULL,
    "time" numeric(10,0) NOT NULL,
    remark character varying(200)
);


ALTER TABLE public.gw_dev_serv OWNER TO gtmsmanager;

--
-- Name: COLUMN gw_dev_serv.serv_state; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_dev_serv.serv_state IS '1:成功
0:未做
-1:失败';


--
-- Name: gw_dev_type; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_dev_type (
    type_id character varying(10) NOT NULL,
    type_name character varying(50) NOT NULL,
    type_desc character varying(100),
    stat_bind_enab numeric(1,0) NOT NULL
);


ALTER TABLE public.gw_dev_type OWNER TO gtmsmanager;

--
-- Name: gw_device_model; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_device_model (
    device_model_id character varying(4) NOT NULL,
    vendor_id character varying(6) NOT NULL,
    device_model character varying(64) NOT NULL,
    prot_id numeric(1,0) DEFAULT 1 NOT NULL,
    add_time numeric(10,0)
);


ALTER TABLE public.gw_device_model OWNER TO gtmsmanager;

--
-- Name: COLUMN gw_device_model.prot_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_device_model.prot_id IS '1:集团设备
2:广东特有设备
3:企智通设备
';


--
-- Name: COLUMN gw_device_model.add_time; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_device_model.add_time IS '秒';


--
-- Name: gw_device_restart_batch; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_device_restart_batch (
    task_id numeric(10,0) NOT NULL,
    device_id character varying(10) NOT NULL,
    add_time numeric(10,0) NOT NULL
);


ALTER TABLE public.gw_device_restart_batch OWNER TO gtmsmanager;

--
-- Name: gw_device_restart_task; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_device_restart_task (
    task_id numeric(10,0) NOT NULL,
    add_time numeric(10,0) NOT NULL,
    start_time numeric(10,0) NOT NULL,
    account_id numeric(10,0) NOT NULL,
    task_desc character varying(50),
    status numeric(2,0) NOT NULL
);


ALTER TABLE public.gw_device_restart_task OWNER TO gtmsmanager;

--
-- Name: gw_devicestatus; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_devicestatus (
    device_id integer NOT NULL,
    online_status smallint DEFAULT 0 NOT NULL,
    last_time numeric(10,0) NOT NULL,
    oper_time numeric(10,0),
    bind_log_stat numeric(2,0) DEFAULT '-1'::integer NOT NULL,
    reboot_time numeric(10,0)
);


ALTER TABLE public.gw_devicestatus OWNER TO gtmsmanager;

--
-- Name: COLUMN gw_devicestatus.device_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_devicestatus.device_id IS '外键:
tab_gw_device(device_id)
';


--
-- Name: COLUMN gw_devicestatus.online_status; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_devicestatus.online_status IS '1:在线
0:不在线
';


--
-- Name: COLUMN gw_devicestatus.bind_log_stat; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_devicestatus.bind_log_stat IS '-1:默认
1:BIND1
2:BIND2';


--
-- Name: gw_devicestatus_history; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_devicestatus_history (
    id integer NOT NULL,
    online_total integer DEFAULT 0 NOT NULL,
    offline_total integer DEFAULT 0 NOT NULL,
    add_date timestamp without time zone NOT NULL,
    add_time timestamp without time zone NOT NULL,
    city integer NOT NULL
);


ALTER TABLE public.gw_devicestatus_history OWNER TO gtmsmanager;

--
-- Name: COLUMN gw_devicestatus_history.add_date; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_devicestatus_history.add_date IS '创建日期';


--
-- Name: COLUMN gw_devicestatus_history.add_time; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_devicestatus_history.add_time IS '创建时间';


--
-- Name: gw_egw_expert; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_egw_expert (
    id numeric(5,0) NOT NULL,
    ex_name character varying(50),
    ex_regular character varying(50),
    ex_bias character varying(50),
    ex_succ_desc character varying(50),
    ex_fault_desc character varying(200),
    ex_suggest character varying(200),
    ex_desc character varying(100)
);


ALTER TABLE public.gw_egw_expert OWNER TO gtmsmanager;

--
-- Name: gw_exception; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_exception (
    exception_time numeric(10,0) NOT NULL,
    gather_id character varying(10) NOT NULL,
    device_id character varying(10) NOT NULL,
    type numeric(2,0) NOT NULL,
    status numeric(1,0) NOT NULL,
    result_id numeric(1,0),
    result_desc character varying(200),
    deal_time numeric(10,0),
    acc_oid numeric(10,0),
    acs_config character varying(100),
    cpe_config character varying(100)
);


ALTER TABLE public.gw_exception OWNER TO gtmsmanager;

--
-- Name: COLUMN gw_exception.type; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_exception.type IS '1: 认证不通过
2: 定制终端ID 不存在
3: 定制终端ID、宽带帐号不匹配
4: 定制终端ID、IP 地址不匹配
';


--
-- Name: COLUMN gw_exception.status; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_exception.status IS '0: 未处理
1: 已处理
';


--
-- Name: COLUMN gw_exception.result_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_exception.result_id IS '0: 处理失败
1: 处理成功
';


--
-- Name: COLUMN gw_exception.acs_config; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_exception.acs_config IS '针对type:
3:系统宽带帐号
4:设备宽带帐号
';


--
-- Name: COLUMN gw_exception.cpe_config; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_exception.cpe_config IS '针对type:
3:系统存放的设备IP
4:设备的实际IP
';


--
-- Name: gw_fire_wall; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_fire_wall (
    device_id character varying(20) NOT NULL,
    gather_time numeric(10,0) NOT NULL,
    enable character varying(10),
    capability character varying(100),
    ddos_enabled numeric(2,0),
    portscan_enabled numeric(2,0)
);


ALTER TABLE public.gw_fire_wall OWNER TO gtmsmanager;

--
-- Name: gw_ipmain; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_ipmain (
    subnet character varying(15) NOT NULL,
    inetmask numeric(65,0) NOT NULL,
    city_id character varying(50) NOT NULL,
    country character varying(50),
    purpose1 character varying(30),
    purpose2 character varying(30),
    purpose3 character varying(30),
    subnetcomment character varying(255)
);


ALTER TABLE public.gw_ipmain OWNER TO gtmsmanager;

--
-- Name: gw_iptv; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_iptv (
    device_id character varying(10) NOT NULL,
    gather_time numeric(10,0) NOT NULL,
    igmp_enab numeric(1,0),
    stb_number numeric(3,0),
    proxy_enable numeric(1,0),
    snooping_enable numeric(1,0)
);


ALTER TABLE public.gw_iptv OWNER TO gtmsmanager;

--
-- Name: gw_iptv_bbms; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_iptv_bbms (
    device_id character varying(10) NOT NULL,
    gather_time numeric(10,0) NOT NULL,
    igmp_enab numeric(1,0),
    stb_number numeric(3,0),
    proxy_enable numeric(1,0),
    snooping_enable numeric(1,0)
);


ALTER TABLE public.gw_iptv_bbms OWNER TO gtmsmanager;

--
-- Name: gw_lan_eth; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_lan_eth (
    device_id character varying(50) NOT NULL,
    lan_id numeric(2,0) NOT NULL,
    lan_eth_id numeric(2,0) NOT NULL,
    enable numeric(1,0),
    status character varying(20),
    mac_address character varying(50),
    gather_time numeric(10,0),
    max_bit_rate character varying(10),
    dupl_mode character varying(10),
    byte_sent numeric(20,0),
    byte_rece numeric(20,0),
    pack_sent numeric(20,0),
    pack_rece numeric(20,0),
    error_sent numeric(20,0),
    drop_sent numeric(20,0),
    error_rece numeric(20,0),
    drop_rece numeric(20,0)
);


ALTER TABLE public.gw_lan_eth OWNER TO gtmsmanager;

--
-- Name: gw_lan_eth_history; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_lan_eth_history (
    device_id character varying(50) NOT NULL,
    lan_id numeric(2,0) NOT NULL,
    lan_eth_id numeric(2,0) NOT NULL,
    enable numeric(1,0),
    status character varying(20),
    mac_address character varying(50),
    gather_time numeric(10,0),
    max_bit_rate character varying(10),
    dupl_mode character varying(10),
    byte_sent numeric(20,0),
    byte_rece numeric(20,0),
    pack_sent numeric(20,0),
    pack_rece numeric(20,0),
    error_sent numeric(20,0),
    drop_sent numeric(20,0),
    error_rece numeric(20,0),
    drop_rece numeric(20,0)
);


ALTER TABLE public.gw_lan_eth_history OWNER TO gtmsmanager;

--
-- Name: gw_lan_eth_namechange; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_lan_eth_namechange (
    device_id character varying(50) NOT NULL,
    lan_id numeric(2,0) NOT NULL,
    lan_eth_id numeric(2,0) NOT NULL,
    mac_address character varying(50),
    gather_time numeric(10,0),
    id numeric(10,0)
);


ALTER TABLE public.gw_lan_eth_namechange OWNER TO gtmsmanager;

--
-- Name: gw_lan_host; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_lan_host (
    device_id character varying(10) NOT NULL,
    lan_inst numeric(3,0) NOT NULL,
    host_inst numeric(3,0) NOT NULL,
    ipaddress character varying(15),
    address_source character varying(30),
    mac_address character varying(50),
    hostname character varying(50),
    active character varying(10),
    update_time numeric(10,0) NOT NULL,
    layer_2_interface character varying(120)
);


ALTER TABLE public.gw_lan_host OWNER TO gtmsmanager;

--
-- Name: gw_lan_host_bbms; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_lan_host_bbms (
    device_id character varying(10) NOT NULL,
    lan_inst numeric(3,0) NOT NULL,
    host_inst numeric(3,0) NOT NULL,
    ipaddress character varying(15),
    address_source character varying(30),
    mac_address character varying(50),
    hostname character varying(50),
    active character varying(10),
    update_time numeric(10,0) NOT NULL,
    layer2interface character varying(100)
);


ALTER TABLE public.gw_lan_host_bbms OWNER TO gtmsmanager;

--
-- Name: gw_lan_host_history; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_lan_host_history (
    device_id character varying(10) NOT NULL,
    lan_inst numeric(3,0) NOT NULL,
    host_inst numeric(3,0) NOT NULL,
    ipaddress character varying(15),
    address_source character varying(30),
    mac_address character varying(50),
    hostname character varying(50),
    active character varying(10),
    update_time numeric(10,0) NOT NULL,
    layer_2_interface character varying(120)
);


ALTER TABLE public.gw_lan_host_history OWNER TO gtmsmanager;

--
-- Name: gw_lan_hostconf; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_lan_hostconf (
    device_id character varying(10) NOT NULL,
    gather_time numeric(10,0) NOT NULL,
    lan_id numeric(3,0) NOT NULL,
    server_conf_enab numeric(1,0),
    server_enab numeric(1,0),
    dhcp_relay numeric(1,0),
    max_addr character varying(20),
    min_addr character varying(20),
    rese_addr text,
    lease_time numeric(10,0),
    allow_mac text,
    stb_max_addr character varying(20),
    stb_min_addr character varying(20),
    phone_max_addr character varying(20),
    phone_min_addr character varying(20),
    came_max_addr character varying(20),
    came_min_addr character varying(20),
    pc_max_addr character varying(20),
    pc_min_addr character varying(20)
);


ALTER TABLE public.gw_lan_hostconf OWNER TO gtmsmanager;

--
-- Name: gw_lan_hostconf_bbms; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_lan_hostconf_bbms (
    device_id character varying(10) NOT NULL,
    gather_time numeric(10,0) NOT NULL,
    lan_id numeric(3,0) NOT NULL,
    server_conf_enab numeric(1,0),
    server_enab numeric(1,0),
    dhcp_relay numeric(1,0),
    max_addr character varying(20),
    min_addr character varying(20),
    rese_addr text,
    lease_time numeric(10,0),
    allow_mac text,
    stb_max_addr character varying(20),
    stb_min_addr character varying(20),
    phone_max_addr character varying(20),
    phone_min_addr character varying(20),
    came_max_addr character varying(20),
    came_min_addr character varying(20),
    pc_max_addr character varying(20),
    pc_min_addr character varying(20)
);


ALTER TABLE public.gw_lan_hostconf_bbms OWNER TO gtmsmanager;

--
-- Name: gw_lan_hostconf_history; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_lan_hostconf_history (
    device_id character varying(10) NOT NULL,
    gather_time numeric(10,0) NOT NULL,
    lan_id numeric(3,0) NOT NULL,
    server_conf_enab numeric(1,0),
    server_enab numeric(1,0),
    dhcp_relay numeric(1,0),
    max_addr character varying(20),
    min_addr character varying(20),
    rese_addr text,
    lease_time numeric(10,0),
    allow_mac text,
    stb_max_addr character varying(20),
    stb_min_addr character varying(20),
    phone_max_addr character varying(20),
    phone_min_addr character varying(20),
    came_max_addr character varying(20),
    came_min_addr character varying(20),
    pc_max_addr character varying(20),
    pc_min_addr character varying(20)
);


ALTER TABLE public.gw_lan_hostconf_history OWNER TO gtmsmanager;

--
-- Name: gw_lan_vlan_dhcp; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_lan_vlan_dhcp (
    device_id character varying(10) NOT NULL,
    vlan_i numeric(3,0) NOT NULL,
    vlan_id numeric(5,0),
    gather_time numeric(10,0) NOT NULL,
    vlan_name character varying(100),
    port_list text,
    ip_enable numeric(1,0),
    ip_address character varying(50),
    ip_mask character varying(50),
    ip_address_type character varying(50),
    dhcp_enable numeric(1,0),
    dhcp_min_addr character varying(50),
    dhcp_max_addr character varying(50),
    dhcp_res_addr character varying(50),
    dhcp_mask character varying(50),
    dhcp_dns character varying(50),
    dhcp_domain character varying(50),
    dhcp_gateway character varying(50),
    dhcp_lease_time numeric(5,0)
);


ALTER TABLE public.gw_lan_vlan_dhcp OWNER TO gtmsmanager;

--
-- Name: gw_lan_vlan_num; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_lan_vlan_num (
    device_id character varying(50) NOT NULL,
    gather_time numeric(10,0),
    vlan_max_num numeric(5,0),
    vlan_cur_num numeric(5,0)
);


ALTER TABLE public.gw_lan_vlan_num OWNER TO gtmsmanager;

--
-- Name: gw_lan_wlan; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_lan_wlan (
    device_id character varying(10) NOT NULL,
    lan_id numeric(2,0) NOT NULL,
    lan_wlan_id numeric(3,0) NOT NULL,
    gather_time numeric(10,0),
    ap_enable numeric(1,0),
    powerlevel numeric(2,0),
    powervalue numeric(5,0),
    enable numeric(1,0),
    ssid character varying(50),
    standard character varying(20),
    beacontype character varying(20),
    basic_auth_mode character varying(20),
    wep_encr_level character varying(20),
    wep_key character varying(200),
    wpa_auth_mode character varying(50),
    wpa_encr_mode character varying(50),
    wpa_key character varying(200),
    radio_enable numeric(1,0),
    hide numeric(1,0),
    poss_channel character varying(50),
    channel numeric(5,0),
    channel_in_use character varying(50),
    status character varying(50),
    wps_key_word numeric(3,0),
    associated_num numeric(20,0),
    ieee_auth_mode character varying(20),
    ieee_encr_mode character varying(50)
);


ALTER TABLE public.gw_lan_wlan OWNER TO gtmsmanager;

--
-- Name: COLUMN gw_lan_wlan.ap_enable; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_lan_wlan.ap_enable IS 'X_CT-COM_APModuleEnable可选值：
1：开启
0：未开
类型:boolean
';


--
-- Name: COLUMN gw_lan_wlan.powerlevel; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_lan_wlan.powerlevel IS 'X_CT-COM_Powerlevel
取值范围：{1,2,3,4,5}，
1 为最大， 5 为最小率。
类型:unsignedInt
';


--
-- Name: COLUMN gw_lan_wlan.enable; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_lan_wlan.enable IS 'Enable可选值：
1:可用
0:不可用
';


--
-- Name: COLUMN gw_lan_wlan.radio_enable; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_lan_wlan.radio_enable IS 'RadioEnabled
1:可用
0:不可用
类型:boolean
';


--
-- Name: COLUMN gw_lan_wlan.hide; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_lan_wlan.hide IS 'X_CT-COM_SSIDHide
1: 是
0: 否(默认)
类型:boolean
';


--
-- Name: COLUMN gw_lan_wlan.channel; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_lan_wlan.channel IS 'Channel
0：表示自动选择信道（网关
自动选择的信道值通过
ChannelsInUse 读取）
1～255：实际信道值
类型:unsignedInt
';


--
-- Name: gw_lan_wlan_bbms; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_lan_wlan_bbms (
    device_id character varying(10) NOT NULL,
    lan_id numeric(2,0) NOT NULL,
    lan_wlan_id numeric(3,0) NOT NULL,
    gather_time numeric(10,0),
    ap_enable numeric(1,0),
    powerlevel numeric(2,0),
    powervalue numeric(5,0),
    enable numeric(1,0),
    ssid character varying(50),
    standard character varying(20),
    beacontype character varying(20),
    basic_auth_mode character varying(20),
    wep_encr_level character varying(20),
    wep_key character varying(200),
    wpa_auth_mode character varying(50),
    wpa_encr_mode character varying(50),
    wpa_key character varying(200),
    radio_enable numeric(1,0),
    hide numeric(1,0),
    poss_channel character varying(50),
    channel numeric(5,0),
    channel_in_use character varying(50),
    status character varying(50),
    wps_key_word numeric(3,0),
    associated_num numeric(20,0),
    ieee_auth_mode character varying(20),
    ieee_encr_mode character varying(50),
    total_bytes_sent numeric(20,0),
    total_bytes_received numeric(20,0),
    total_packets_sent numeric(20,0),
    total_packets_received numeric(20,0)
);


ALTER TABLE public.gw_lan_wlan_bbms OWNER TO gtmsmanager;

--
-- Name: COLUMN gw_lan_wlan_bbms.ap_enable; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_lan_wlan_bbms.ap_enable IS 'X_CT-COM_APModuleEnable��������
1������
0������
����:boolean';


--
-- Name: COLUMN gw_lan_wlan_bbms.powerlevel; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_lan_wlan_bbms.powerlevel IS 'X_CT-COM_Powerlevel
����������{1,2,3,4,5}��
1 �������� 5 ����������
����:unsignedInt';


--
-- Name: COLUMN gw_lan_wlan_bbms.enable; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_lan_wlan_bbms.enable IS 'Enable��������
1:����
0:������';


--
-- Name: COLUMN gw_lan_wlan_bbms.radio_enable; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_lan_wlan_bbms.radio_enable IS 'RadioEnabled
1:����
0:������
����:boolean';


--
-- Name: COLUMN gw_lan_wlan_bbms.hide; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_lan_wlan_bbms.hide IS 'X_CT-COM_SSIDHide
1: ��
0: ��(����)
����:boolean';


--
-- Name: COLUMN gw_lan_wlan_bbms.channel; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_lan_wlan_bbms.channel IS 'Channel
0������������������������
��������������������
ChannelsInUse ������
1��255������������
����:unsignedInt';


--
-- Name: gw_lan_wlan_health; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_lan_wlan_health (
    device_id character varying(10) NOT NULL,
    lan_id numeric(2,0) NOT NULL,
    lan_wlan_id numeric(3,0) NOT NULL,
    gather_time numeric(10,0) NOT NULL,
    powerlevel numeric(2,0) NOT NULL,
    powervalue numeric(5,0)
);


ALTER TABLE public.gw_lan_wlan_health OWNER TO gtmsmanager;

--
-- Name: gw_lan_wlan_history; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_lan_wlan_history (
    device_id character varying(10) NOT NULL,
    lan_id numeric(2,0) NOT NULL,
    lan_wlan_id numeric(3,0) NOT NULL,
    gather_time numeric(10,0) NOT NULL,
    ap_enable numeric(1,0),
    powerlevel numeric(2,0),
    powervalue numeric(5,0),
    enable numeric(1,0),
    ssid character varying(50),
    standard character varying(20),
    beacontype character varying(20),
    basic_auth_mode character varying(20),
    wep_encr_level character varying(20),
    wep_key character varying(200),
    wpa_auth_mode character varying(50),
    wpa_encr_mode character varying(50),
    wpa_key character varying(200),
    radio_enable numeric(1,0),
    hide numeric(1,0),
    poss_channel character varying(50),
    channel numeric(5,0),
    channel_in_use character varying(50),
    status character varying(50),
    wps_key_word numeric(3,0),
    associated_num numeric(20,0),
    ieee_auth_mode character varying(20),
    ieee_encr_mode character varying(50),
    total_bytes_sent numeric(20,0),
    total_bytes_received numeric(20,0),
    total_packets_sent numeric(20,0),
    total_packets_received numeric(20,0)
);


ALTER TABLE public.gw_lan_wlan_history OWNER TO gtmsmanager;

--
-- Name: COLUMN gw_lan_wlan_history.ap_enable; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_lan_wlan_history.ap_enable IS 'X_CT-COM_APModuleEnable��������
1������
0������
����:boolean';


--
-- Name: COLUMN gw_lan_wlan_history.powerlevel; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_lan_wlan_history.powerlevel IS 'X_CT-COM_Powerlevel
����������{1,2,3,4,5}��
1 �������� 5 ����������
����:unsignedInt';


--
-- Name: COLUMN gw_lan_wlan_history.enable; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_lan_wlan_history.enable IS 'Enable��������
1:����
0:������';


--
-- Name: COLUMN gw_lan_wlan_history.radio_enable; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_lan_wlan_history.radio_enable IS 'RadioEnabled
1:����
0:������
����:boolean';


--
-- Name: COLUMN gw_lan_wlan_history.hide; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_lan_wlan_history.hide IS 'X_CT-COM_SSIDHide
1: ��
0: ��(����)
����:boolean';


--
-- Name: COLUMN gw_lan_wlan_history.channel; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_lan_wlan_history.channel IS 'Channel
0������������������������
��������������������
ChannelsInUse ������
1��255������������
����:unsignedInt';


--
-- Name: gw_lan_wlan_namechange; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_lan_wlan_namechange (
    device_id character varying(10) NOT NULL,
    lan_id numeric(2,0) NOT NULL,
    lan_wlan_id numeric(3,0) NOT NULL,
    ssid character varying(50),
    gather_time numeric(10,0),
    id numeric(10,0)
);


ALTER TABLE public.gw_lan_wlan_namechange OWNER TO gtmsmanager;

--
-- Name: gw_monitor_task; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_monitor_task (
    task_id numeric(10,0) NOT NULL,
    device_id character varying(10) NOT NULL,
    "interval" numeric(3,0) NOT NULL,
    times numeric(5,0) NOT NULL,
    start_time numeric(10,0) NOT NULL,
    end_time numeric(10,0) NOT NULL,
    status numeric(2,0) NOT NULL
);


ALTER TABLE public.gw_monitor_task OWNER TO gtmsmanager;

--
-- Name: gw_mwband; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_mwband (
    device_id character varying(10) NOT NULL,
    m_mode numeric(2,0) NOT NULL,
    gather_time numeric(10,0) NOT NULL,
    total_number numeric(5,0),
    stb_enable numeric(1,0),
    stb_number numeric(5,0),
    camera_enable numeric(1,0),
    camera_number numeric(5,0),
    computer_enable numeric(1,0),
    computer_number numeric(5,0),
    phone_enable numeric(1,0),
    phone_number numeric(5,0)
);


ALTER TABLE public.gw_mwband OWNER TO gtmsmanager;

--
-- Name: COLUMN gw_mwband.m_mode; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_mwband.m_mode IS 'Mode
0:不限制
1: 模式一.限制总数
2: 模式二.详细限制
类型:int
';


--
-- Name: COLUMN gw_mwband.stb_enable; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_mwband.stb_enable IS 'STBRestrictEnable
针对模式二
1:限制
0:不
类型:int
';


--
-- Name: COLUMN gw_mwband.camera_enable; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_mwband.camera_enable IS 'CameraRestrictEnable
针对模式二
1:限制
0:不
类型:int
';


--
-- Name: COLUMN gw_mwband.computer_enable; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_mwband.computer_enable IS 'ComputerRestrictEnable
针对模式二
1:限制
0:不
类型:int
';


--
-- Name: COLUMN gw_mwband.phone_enable; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_mwband.phone_enable IS 'PhoneRestrictEnable
针对模式二
1:限制
0:不
类型:int
';


--
-- Name: gw_mwband_bbms; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_mwband_bbms (
    device_id character varying(10) NOT NULL,
    m_mode numeric(2,0) NOT NULL,
    gather_time numeric(10,0) NOT NULL,
    total_number numeric(5,0),
    stb_enable numeric(1,0),
    stb_number numeric(5,0),
    camera_enable numeric(1,0),
    camera_number numeric(5,0),
    computer_enable numeric(1,0),
    computer_number numeric(5,0),
    phone_enable numeric(1,0),
    phone_number numeric(5,0)
);


ALTER TABLE public.gw_mwband_bbms OWNER TO gtmsmanager;

--
-- Name: COLUMN gw_mwband_bbms.m_mode; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_mwband_bbms.m_mode IS 'Mode
0:不限制
1: 模式一.限制总数
2: 模式二.详细限制
类型:int';


--
-- Name: COLUMN gw_mwband_bbms.stb_enable; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_mwband_bbms.stb_enable IS 'STBRestrictEnable
针对模式二
1:限制
0:不
类型:int';


--
-- Name: COLUMN gw_mwband_bbms.camera_enable; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_mwband_bbms.camera_enable IS 'CameraRestrictEnable
针对模式二
1:限制
0:不
类型:int';


--
-- Name: COLUMN gw_mwband_bbms.computer_enable; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_mwband_bbms.computer_enable IS 'ComputerRestrictEnable
针对模式二
1:限制
0:不
类型:int
';


--
-- Name: COLUMN gw_mwband_bbms.phone_enable; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_mwband_bbms.phone_enable IS 'PhoneRestrictEnable
针对模式二
1:限制
0:不
类型:int
';


--
-- Name: gw_office_voip; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_office_voip (
    office_id character varying(20) NOT NULL,
    proxy_server character varying(60) NOT NULL,
    proxy_port numeric(5,0) NOT NULL,
    standby_proxy_server character varying(60),
    standby_proxy_port numeric(5,0),
    regist_server character varying(60),
    regist_port numeric(5,0),
    standby_regist_server character varying(60),
    standby_regist_port numeric(5,0),
    outbound_proxy character varying(60),
    outbound_port numeric(5,0),
    standby_outbound_proxy character varying(60),
    standby_outbound_port numeric(5,0)
);


ALTER TABLE public.gw_office_voip OWNER TO gtmsmanager;

--
-- Name: gw_online_config; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_online_config (
    time_point numeric(10,0) NOT NULL,
    city_id character varying(20) NOT NULL,
    config_time numeric(10,0)
);


ALTER TABLE public.gw_online_config OWNER TO gtmsmanager;

--
-- Name: gw_online_report; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_online_report (
    city_id character varying(20) NOT NULL,
    r_time numeric(10,0),
    r_count numeric(10,0),
    r_timepoint numeric(10,0) NOT NULL
);


ALTER TABLE public.gw_online_report OWNER TO gtmsmanager;

--
-- Name: gw_order_type; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_order_type (
    type_id numeric(6,0) NOT NULL,
    type_name character varying(50) NOT NULL,
    type_desc character varying(100),
    stat_bind_enab numeric(1,0) NOT NULL,
    _no_pk_hash character varying(64)
);


ALTER TABLE public.gw_order_type OWNER TO gtmsmanager;

--
-- Name: gw_ping; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_ping (
    device_id character varying(20) NOT NULL,
    "time" numeric(10,0) NOT NULL,
    device_port character varying(200),
    test_ip character varying(50),
    package_size numeric(10,0),
    package_num numeric(10,0),
    time_out numeric(10,0),
    succ_num numeric(10,0),
    fail_num numeric(10,0),
    avg_res_time numeric(10,0),
    min_res_time numeric(10,0),
    max_res_time numeric(10,0),
    is_ping_succ numeric(1,0)
);


ALTER TABLE public.gw_ping OWNER TO gtmsmanager;

--
-- Name: gw_qos; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_qos (
    device_id character varying(10) NOT NULL,
    gather_time numeric(10,0) NOT NULL,
    enable numeric(1,0),
    qos_mode character varying(50),
    qos_plan character varying(10),
    bandwidth numeric(10,0),
    enab_width numeric(1,0),
    enab_dscp numeric(1,0),
    enab_802p numeric(1,0)
);


ALTER TABLE public.gw_qos OWNER TO gtmsmanager;

--
-- Name: COLUMN gw_qos.qos_mode; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_qos.qos_mode IS 'TR069,
INTERNET,
IPTV,
VOIP,
OTHER';


--
-- Name: COLUMN gw_qos.qos_plan; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_qos.qos_plan IS 'priority
weight';


--
-- Name: COLUMN gw_qos.enab_width; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_qos.enab_width IS 'EnableForceWeight';


--
-- Name: COLUMN gw_qos.enab_dscp; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_qos.enab_dscp IS 'EnableDSCPMark';


--
-- Name: COLUMN gw_qos.enab_802p; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_qos.enab_802p IS 'Enable802-1_P';


--
-- Name: gw_qos_app; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_qos_app (
    device_id character varying(10) NOT NULL,
    gather_time numeric(10,0) NOT NULL,
    app_id numeric(2,0) NOT NULL,
    app_name character varying(50),
    queue_id numeric(1,0)
);


ALTER TABLE public.gw_qos_app OWNER TO gtmsmanager;

--
-- Name: COLUMN gw_qos_app.queue_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_qos_app.queue_id IS '1,
2,
3,
4';


--
-- Name: gw_qos_app_bbms; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_qos_app_bbms (
    device_id character varying(10) NOT NULL,
    gather_time numeric(10,0) NOT NULL,
    app_id numeric(2,0) NOT NULL,
    app_name character varying(50),
    queue_id numeric(1,0)
);


ALTER TABLE public.gw_qos_app_bbms OWNER TO gtmsmanager;

--
-- Name: COLUMN gw_qos_app_bbms.queue_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_qos_app_bbms.queue_id IS '1,
2,
3,
4';


--
-- Name: gw_qos_bbms; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_qos_bbms (
    device_id character varying(10) NOT NULL,
    gather_time numeric(10,0) NOT NULL,
    enable numeric(1,0),
    qos_mode character varying(50),
    qos_plan character varying(10),
    bandwidth numeric(10,0),
    enab_width numeric(1,0),
    enab_dscp numeric(1,0),
    enab_802p numeric(1,0)
);


ALTER TABLE public.gw_qos_bbms OWNER TO gtmsmanager;

--
-- Name: COLUMN gw_qos_bbms.qos_mode; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_qos_bbms.qos_mode IS 'TR069,
INTERNET,
IPTV,
VOIP,
OTHER';


--
-- Name: COLUMN gw_qos_bbms.qos_plan; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_qos_bbms.qos_plan IS 'priority
weight';


--
-- Name: COLUMN gw_qos_bbms.enab_width; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_qos_bbms.enab_width IS 'EnableForceWeight';


--
-- Name: COLUMN gw_qos_bbms.enab_dscp; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_qos_bbms.enab_dscp IS 'EnableDSCPMark';


--
-- Name: COLUMN gw_qos_bbms.enab_802p; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_qos_bbms.enab_802p IS 'Enable802-1_P';


--
-- Name: gw_qos_class; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_qos_class (
    device_id character varying(10) NOT NULL,
    gather_time numeric(10,0) NOT NULL,
    class_id numeric(2,0) NOT NULL,
    queue_id numeric(1,0),
    value_dscp numeric(10,0),
    value_8021p numeric(10,0)
);


ALTER TABLE public.gw_qos_class OWNER TO gtmsmanager;

--
-- Name: COLUMN gw_qos_class.queue_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_qos_class.queue_id IS '1,
2,
3,
4';


--
-- Name: gw_qos_class_bbms; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_qos_class_bbms (
    device_id character varying(10) NOT NULL,
    gather_time numeric(10,0) NOT NULL,
    class_id numeric(2,0) NOT NULL,
    queue_id numeric(1,0),
    value_dscp numeric(10,0),
    value_8021p numeric(10,0)
);


ALTER TABLE public.gw_qos_class_bbms OWNER TO gtmsmanager;

--
-- Name: COLUMN gw_qos_class_bbms.queue_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_qos_class_bbms.queue_id IS '1,
2,
3,
4';


--
-- Name: gw_qos_class_type; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_qos_class_type (
    device_id character varying(10) NOT NULL,
    gather_time numeric(10,0) NOT NULL,
    class_id numeric(2,0) NOT NULL,
    type_id numeric(1,0) NOT NULL,
    type_name character varying(50),
    type_max text,
    type_min text,
    type_prot character varying(200)
);


ALTER TABLE public.gw_qos_class_type OWNER TO gtmsmanager;

--
-- Name: COLUMN gw_qos_class_type.type_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_qos_class_type.type_id IS '1';


--
-- Name: COLUMN gw_qos_class_type.type_name; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_qos_class_type.type_name IS 'SIP,
DIP,
SPORT,
DPORT,
8021P,
LANInterface,
WANInterface...';


--
-- Name: COLUMN gw_qos_class_type.type_prot; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_qos_class_type.type_prot IS 'TCP,
UDP,
ICMP...';


--
-- Name: gw_qos_class_type_bbms; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_qos_class_type_bbms (
    device_id character varying(10) NOT NULL,
    gather_time numeric(10,0) NOT NULL,
    class_id numeric(2,0) NOT NULL,
    type_id numeric(1,0) NOT NULL,
    type_name character varying(50),
    type_max text,
    type_min text,
    type_prot character varying(200)
);


ALTER TABLE public.gw_qos_class_type_bbms OWNER TO gtmsmanager;

--
-- Name: COLUMN gw_qos_class_type_bbms.type_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_qos_class_type_bbms.type_id IS '1';


--
-- Name: COLUMN gw_qos_class_type_bbms.type_name; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_qos_class_type_bbms.type_name IS 'SIP,
DIP,
SPORT,
DPORT,
8021P,
LANInterface,
WANInterface...';


--
-- Name: COLUMN gw_qos_class_type_bbms.type_prot; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_qos_class_type_bbms.type_prot IS 'TCP,
UDP,
ICMP...';


--
-- Name: gw_qos_queue; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_qos_queue (
    device_id character varying(50) NOT NULL,
    gather_time numeric(10,0),
    queue_id numeric(1,0) NOT NULL,
    enable numeric(1,0),
    priority numeric(1,0),
    weight numeric(5,0)
);


ALTER TABLE public.gw_qos_queue OWNER TO gtmsmanager;

--
-- Name: COLUMN gw_qos_queue.queue_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_qos_queue.queue_id IS '1,
2,
3,
4';


--
-- Name: gw_qos_queue_bbms; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_qos_queue_bbms (
    device_id character varying(50) NOT NULL,
    gather_time numeric(10,0),
    queue_id numeric(1,0) NOT NULL,
    enable numeric(1,0),
    priority numeric(1,0),
    weight numeric(5,0)
);


ALTER TABLE public.gw_qos_queue_bbms OWNER TO gtmsmanager;

--
-- Name: COLUMN gw_qos_queue_bbms.queue_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_qos_queue_bbms.queue_id IS '1,
2,
3,
4';


--
-- Name: gw_sec_access_control_bbms; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_sec_access_control_bbms (
    device_id character varying(10) NOT NULL,
    enable numeric(2,0),
    gather_time numeric(10,0)
);


ALTER TABLE public.gw_sec_access_control_bbms OWNER TO gtmsmanager;

--
-- Name: gw_sec_antivirus_bbms; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_sec_antivirus_bbms (
    device_id character varying(10) NOT NULL,
    enable numeric(2,0),
    gather_time numeric(10,0)
);


ALTER TABLE public.gw_sec_antivirus_bbms OWNER TO gtmsmanager;

--
-- Name: gw_sec_content_filter_bbms; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_sec_content_filter_bbms (
    device_id character varying(10) NOT NULL,
    http_filter_enabled numeric(2,0),
    file_filter_enable numeric(2,0),
    log_enable numeric(2,0),
    gather_time numeric(10,0)
);


ALTER TABLE public.gw_sec_content_filter_bbms OWNER TO gtmsmanager;

--
-- Name: gw_sec_intrusion_detect_bbms; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_sec_intrusion_detect_bbms (
    device_id character varying(10) NOT NULL,
    enable numeric(2,0),
    gather_time numeric(10,0)
);


ALTER TABLE public.gw_sec_intrusion_detect_bbms OWNER TO gtmsmanager;

--
-- Name: gw_sec_mail_filter_bbms; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_sec_mail_filter_bbms (
    device_id character varying(10) NOT NULL,
    smtp_filter_enabled numeric(2,0),
    pop3_filter_enabled numeric(2,0),
    gather_time numeric(10,0)
);


ALTER TABLE public.gw_sec_mail_filter_bbms OWNER TO gtmsmanager;

--
-- Name: gw_serv_beforehand_id_seq; Type: SEQUENCE; Schema: public; Owner: gtmsmanager
--

CREATE SEQUENCE public.gw_serv_beforehand_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.gw_serv_beforehand_id_seq OWNER TO gtmsmanager;

--
-- Name: gw_serv_beforehand; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_serv_beforehand (
    service_id numeric(4,0) NOT NULL,
    before_id numeric(4,0) NOT NULL,
    before_type numeric(4,0) NOT NULL,
    id integer DEFAULT nextval('public.gw_serv_beforehand_id_seq'::regclass) NOT NULL
);


ALTER TABLE public.gw_serv_beforehand OWNER TO gtmsmanager;

--
-- Name: COLUMN gw_serv_beforehand.before_type; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_serv_beforehand.before_type IS '1：预读PVC
2：预读绑定端口
3：预读无线
4：业务下发
5: 版本比较
';


--
-- Name: gw_serv_default; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_serv_default (
    serv_default_id numeric(4,0) NOT NULL,
    new_nable numeric(1,0),
    is_default numeric(1,0),
    remark character varying(200)
);


ALTER TABLE public.gw_serv_default OWNER TO gtmsmanager;

--
-- Name: COLUMN gw_serv_default.serv_default_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_serv_default.serv_default_id IS '和conf_tmpl表中的temp_id保持一致';


--
-- Name: COLUMN gw_serv_default.new_nable; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_serv_default.new_nable IS '1:仅新设备做
0:所有设备都做
';


--
-- Name: COLUMN gw_serv_default.is_default; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_serv_default.is_default IS '0：不需要采集设备的上行方式
1：需要采集';


--
-- Name: gw_serv_default_value; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_serv_default_value (
    serv_type_id numeric(4,0) NOT NULL,
    oper_type_id numeric(4,0) NOT NULL,
    city_id character varying(10),
    pvc character varying(10),
    vlan_id character varying(10),
    bind_port character varying(50)
);


ALTER TABLE public.gw_serv_default_value OWNER TO gtmsmanager;

--
-- Name: gw_serv_package; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_serv_package (
    serv_package_id character varying(10) NOT NULL,
    serv_package_name character varying(50) NOT NULL,
    serv_package_desc character varying(100),
    stat_bind_enab numeric(1,0) NOT NULL
);


ALTER TABLE public.gw_serv_package OWNER TO gtmsmanager;

--
-- Name: COLUMN gw_serv_package.stat_bind_enab; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_serv_package.stat_bind_enab IS 'gw_serv_package';


--
-- Name: gw_serv_package_type; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_serv_package_type (
    serv_package_id character varying(10) NOT NULL,
    serv_type_id numeric(4,0) NOT NULL
);


ALTER TABLE public.gw_serv_package_type OWNER TO gtmsmanager;

--
-- Name: gw_serv_setloid; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_serv_setloid (
    task_id numeric(10,0) NOT NULL,
    order_time numeric(10,0) NOT NULL,
    city_id character varying(20) NOT NULL,
    account_id numeric(10,0),
    flag numeric(1,0) NOT NULL
);


ALTER TABLE public.gw_serv_setloid OWNER TO gtmsmanager;

--
-- Name: gw_serv_strategy; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_serv_strategy (
    id numeric(11,0) NOT NULL,
    status numeric(10,0) DEFAULT 0 NOT NULL,
    result_id numeric(6,0) DEFAULT 0 NOT NULL,
    result_desc text,
    acc_oid numeric(10,0) DEFAULT 1 NOT NULL,
    "time" numeric(10,0) NOT NULL,
    start_time numeric(10,0),
    end_time numeric(10,0),
    type numeric(1,0) DEFAULT 0 NOT NULL,
    gather_id character varying(100),
    device_id character varying(10),
    oui character varying(6),
    device_serialnumber character varying(64),
    username character varying(100),
    sheet_id character varying(100),
    sheet_para text,
    service_id numeric(4,0) NOT NULL,
    task_id character varying(15),
    order_id numeric(4,0),
    exec_count numeric(2,0) DEFAULT 0,
    redo numeric(2,0) DEFAULT 0 NOT NULL,
    sheet_type numeric(1,0) DEFAULT 1,
    temp_id numeric(4,0),
    is_last_one numeric(1,0),
    priority numeric(1,0) DEFAULT 1,
    sub_service_id numeric(4,0),
    line_id numeric(10,0),
    client_id numeric(10,0),
    ids_task_id numeric(20,0)
);


ALTER TABLE public.gw_serv_strategy OWNER TO gtmsmanager;

--
-- Name: COLUMN gw_serv_strategy.status; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_serv_strategy.status IS '0:等待执行
1：预读PVC
2：预读绑定端口
3：预读无线
4：业务下发
100：执行完成
';


--
-- Name: COLUMN gw_serv_strategy.result_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_serv_strategy.result_id IS '策略执行的结果
1:成功
0，2： 中间状态
3：设备无法连接
4：提示：设备未配置iTV有线，故无法继续配置无线

other:失败

';


--
-- Name: COLUMN gw_serv_strategy.type; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_serv_strategy.type IS '0:立即执行
1：第一次连到系统
2：周期上报
3：重新启动
4：下次连到系统
5: 设备启动
';


--
-- Name: COLUMN gw_serv_strategy.sheet_type; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_serv_strategy.sheet_type IS '1：老工单
2：新工单
';


--
-- Name: COLUMN gw_serv_strategy.sub_service_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_serv_strategy.sub_service_id IS '服务id:service_id 表明是哪个业务 例如：上网、iptv、voip
service_id 加上 wantype 决定 一个服务子ID，
一个sub_service_id决定配置模块采用哪些模板下发工单。';


--
-- Name: COLUMN gw_serv_strategy.line_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_serv_strategy.line_id IS 'PDM缺失字段';


--
-- Name: COLUMN gw_serv_strategy.client_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_serv_strategy.client_id IS 'PDM缺失字段';


--
-- Name: gw_serv_strategy_batch; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_serv_strategy_batch (
    id bigint NOT NULL,
    status bigint DEFAULT 0 NOT NULL,
    result_id integer DEFAULT 0 NOT NULL,
    result_desc character varying(3000),
    acc_oid bigint DEFAULT 1 NOT NULL,
    "time" bigint NOT NULL,
    start_time bigint,
    end_time bigint,
    type smallint DEFAULT 0 NOT NULL,
    gather_id character varying(100),
    device_id character varying(10),
    oui character varying(6),
    device_serialnumber character varying(64),
    username character varying(100),
    sheet_id character varying(100),
    sheet_para character varying(4000),
    service_id smallint NOT NULL,
    task_id character varying(15),
    order_id smallint,
    exec_count smallint DEFAULT 0,
    redo smallint DEFAULT 0 NOT NULL,
    sheet_type smallint DEFAULT 1,
    temp_id smallint,
    is_last_one smallint,
    priority smallint DEFAULT 1,
    sub_service_id smallint,
    line_id bigint,
    client_id bigint,
    ids_task_id numeric(20,0)
);


ALTER TABLE public.gw_serv_strategy_batch OWNER TO gtmsmanager;

--
-- Name: gw_serv_strategy_log; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_serv_strategy_log (
    id bigint NOT NULL,
    status bigint DEFAULT 0 NOT NULL,
    result_id integer DEFAULT 0 NOT NULL,
    result_desc character varying(3000),
    acc_oid bigint DEFAULT 1 NOT NULL,
    "time" bigint NOT NULL,
    start_time bigint,
    end_time bigint,
    type smallint DEFAULT 0 NOT NULL,
    gather_id character varying(100),
    device_id character varying(10),
    oui character varying(6),
    device_serialnumber character varying(64),
    username character varying(100),
    sheet_id character varying(100),
    sheet_para character varying(4000),
    service_id smallint NOT NULL,
    task_id character varying(15),
    order_id smallint,
    exec_count smallint DEFAULT 0,
    redo smallint DEFAULT 0 NOT NULL,
    sheet_type smallint DEFAULT 1,
    temp_id smallint,
    is_last_one smallint,
    priority smallint DEFAULT 1,
    sub_service_id smallint,
    line_id bigint,
    client_id bigint,
    ids_task_id numeric(20,0)
);


ALTER TABLE public.gw_serv_strategy_log OWNER TO gtmsmanager;

--
-- Name: gw_serv_strategy_serv; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_serv_strategy_serv (
    id numeric(11,0) NOT NULL,
    status numeric(10,0) DEFAULT 0 NOT NULL,
    result_id numeric(6,0) DEFAULT 0 NOT NULL,
    result_desc text,
    acc_oid numeric(10,0) DEFAULT 1 NOT NULL,
    "time" numeric(10,0) NOT NULL,
    start_time numeric(10,0),
    end_time numeric(10,0),
    type numeric(1,0) DEFAULT 0 NOT NULL,
    gather_id character varying(100),
    device_id character varying(10),
    oui character varying(6),
    device_serialnumber character varying(64),
    username character varying(100),
    sheet_id character varying(100),
    sheet_para text,
    service_id numeric(4,0) NOT NULL,
    task_id character varying(15),
    order_id numeric(50,0),
    exec_count numeric(2,0) DEFAULT 0,
    redo numeric(2,0) DEFAULT 0 NOT NULL,
    sheet_type numeric(1,0),
    temp_id numeric(4,0),
    is_last_one numeric(1,0),
    priority numeric(1,0) DEFAULT 1,
    sub_service_id numeric(4,0),
    line_id numeric(10,0),
    client_id numeric(10,0),
    ids_task_id numeric(20,0)
);


ALTER TABLE public.gw_serv_strategy_serv OWNER TO gtmsmanager;

--
-- Name: COLUMN gw_serv_strategy_serv.status; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_serv_strategy_serv.status IS '0:????????
1??????PVC
2??????????????
3??????????
4??????????
100??????????
';


--
-- Name: COLUMN gw_serv_strategy_serv.result_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_serv_strategy_serv.result_id IS '??????????????
1:????
0??2?? ????????
3??????????????
4??????????????????iTV????????????????????????
other:????';


--
-- Name: COLUMN gw_serv_strategy_serv.type; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_serv_strategy_serv.type IS '0:????????
1????????????????
2??????????
3??????????
4??????????????
5: ????????';


--
-- Name: COLUMN gw_serv_strategy_serv.sheet_type; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_serv_strategy_serv.sheet_type IS '1????????
2????????';


--
-- Name: COLUMN gw_serv_strategy_serv.sub_service_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_serv_strategy_serv.sub_service_id IS '????id:service_id ?????????????? ????????????iptv??voip
service_id ???? wantype ???? ??????????ID??
????sub_service_id??????????????????????????????????';


--
-- Name: gw_serv_strategy_serv_log; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_serv_strategy_serv_log (
    id numeric(11,0) NOT NULL,
    status numeric(10,0) DEFAULT 0 NOT NULL,
    result_id numeric(6,0) DEFAULT 0 NOT NULL,
    result_desc text,
    acc_oid numeric(10,0) DEFAULT 1 NOT NULL,
    "time" numeric(10,0) NOT NULL,
    start_time numeric(10,0),
    end_time numeric(10,0),
    type numeric(1,0) DEFAULT 0 NOT NULL,
    gather_id character varying(100),
    device_id character varying(10),
    oui character varying(6),
    device_serialnumber character varying(64),
    username character varying(100),
    sheet_id character varying(100),
    sheet_para text,
    service_id numeric(4,0) NOT NULL,
    task_id character varying(15),
    order_id numeric(50,0),
    exec_count numeric(2,0) DEFAULT 0,
    redo numeric(2,0) DEFAULT 0 NOT NULL,
    sheet_type numeric(1,0),
    temp_id numeric(4,0),
    is_last_one numeric(1,0),
    priority numeric(1,0) DEFAULT 1,
    sub_service_id numeric(4,0),
    line_id numeric(10,0),
    client_id numeric(10,0),
    ids_task_id numeric(20,0)
);


ALTER TABLE public.gw_serv_strategy_serv_log OWNER TO gtmsmanager;

--
-- Name: COLUMN gw_serv_strategy_serv_log.sheet_type; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_serv_strategy_serv_log.sheet_type IS '1????????
2????????
';


--
-- Name: gw_serv_strategy_soft; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_serv_strategy_soft (
    id bigint NOT NULL,
    status bigint DEFAULT 0 NOT NULL,
    result_id integer DEFAULT 0 NOT NULL,
    result_desc character varying(3000),
    acc_oid bigint DEFAULT 1 NOT NULL,
    "time" bigint NOT NULL,
    start_time bigint,
    end_time bigint,
    type character varying(10) DEFAULT 0 NOT NULL,
    gather_id character varying(100),
    device_id character varying(10),
    oui character varying(6),
    device_serialnumber character varying(64),
    username character varying(100),
    sheet_id character varying(100),
    sheet_para character varying(4000),
    service_id smallint NOT NULL,
    task_id character varying(15),
    order_id smallint,
    exec_count smallint DEFAULT 0,
    redo smallint DEFAULT 0 NOT NULL,
    sheet_type smallint DEFAULT 1,
    temp_id smallint,
    is_last_one smallint,
    priority smallint DEFAULT 1,
    sub_service_id smallint,
    line_id bigint,
    client_id character varying(10),
    ids_task_id numeric(20,0)
);

ALTER TABLE ONLY public.gw_serv_strategy_soft REPLICA IDENTITY FULL;


ALTER TABLE public.gw_serv_strategy_soft OWNER TO gtmsmanager;

--
-- Name: gw_serv_strategy_soft_log; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_serv_strategy_soft_log (
    id bigint NOT NULL,
    status bigint DEFAULT 0 NOT NULL,
    result_id integer DEFAULT 0 NOT NULL,
    result_desc character varying(3000),
    acc_oid bigint DEFAULT 1 NOT NULL,
    "time" bigint NOT NULL,
    start_time bigint,
    end_time bigint,
    type character varying(10) DEFAULT 0 NOT NULL,
    gather_id character varying(100),
    device_id character varying(10),
    oui character varying(6),
    device_serialnumber character varying(64),
    username character varying(100),
    sheet_id character varying(100),
    sheet_para character varying(4000),
    service_id smallint NOT NULL,
    task_id character varying(15),
    order_id smallint,
    exec_count smallint DEFAULT 0,
    redo smallint DEFAULT 0 NOT NULL,
    sheet_type smallint DEFAULT 1,
    temp_id smallint,
    is_last_one smallint,
    priority smallint DEFAULT 1,
    sub_service_id smallint,
    line_id bigint,
    client_id character varying(10),
    ids_task_id character varying(50)
);

ALTER TABLE ONLY public.gw_serv_strategy_soft_log REPLICA IDENTITY FULL;


ALTER TABLE public.gw_serv_strategy_soft_log OWNER TO gtmsmanager;

--
-- Name: gw_serv_type_device_type; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_serv_type_device_type (
    serv_type_id numeric(4,0) NOT NULL,
    device_type character varying(50) NOT NULL
);


ALTER TABLE public.gw_serv_type_device_type OWNER TO gtmsmanager;

--
-- Name: gw_setloid_device; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_setloid_device (
    task_id numeric(10,0) NOT NULL,
    device_id character varying(10) NOT NULL,
    device_serialnumber character varying(64) NOT NULL,
    loid character varying(40) NOT NULL,
    status numeric(1,0) NOT NULL,
    update_time numeric(10,0)
);


ALTER TABLE public.gw_setloid_device OWNER TO gtmsmanager;

--
-- Name: gw_soft_record; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_soft_record (
    device_id character varying(50),
    oui character varying(6),
    sn character varying(64),
    username character varying(40),
    city_id character varying(20),
    devicetype_id numeric(4,0),
    type numeric(2,0),
    is_test numeric(1,0),
    part numeric(2,0)
);


ALTER TABLE public.gw_soft_record OWNER TO gtmsmanager;

--
-- Name: COLUMN gw_soft_record.type; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_soft_record.type IS '1：华为B芯片，devicetype_id=(436, 728)
2：大亚V6.1.3
3：中兴，devicetype_id=(342,364)
4：中兴，devicetype_id=(387,403,719)
5：贝尔AA，devicetype_id !=(608,609)
6：贝尔AC，devicetype_id=(608,609)
7：贝曼
8：华为C芯片
9：大亚V6.2.3
10：中兴，devicetype_id=(165,497)
11：中兴，devicetype_id=(176,207)';


--
-- Name: COLUMN gw_soft_record.is_test; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_soft_record.is_test IS '1：比如测试200台
0：正式全网配置';


--
-- Name: COLUMN gw_soft_record.part; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_soft_record.part IS '同一类型设备太多，每次配置为part1, part2......
暂时
part1表示属地南京
part2表示属地苏州
...';


--
-- Name: gw_soft_upgrade_temp; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_soft_upgrade_temp (
    temp_id numeric(4,0) NOT NULL,
    temp_name character varying(30) NOT NULL,
    acc_oid numeric(20,0) NOT NULL,
    "time" numeric(10,0) NOT NULL,
    temp_desc character varying(100),
    remark character varying(100)
);


ALTER TABLE public.gw_soft_upgrade_temp OWNER TO gtmsmanager;

--
-- Name: gw_soft_upgrade_temp_map; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_soft_upgrade_temp_map (
    temp_id numeric(4,0) NOT NULL,
    devicetype_id_old numeric(20,0) NOT NULL,
    devicetype_id numeric(20,0) NOT NULL,
    city_id character varying(8)
);

ALTER TABLE ONLY public.gw_soft_upgrade_temp_map REPLICA IDENTITY FULL;


ALTER TABLE public.gw_soft_upgrade_temp_map OWNER TO gtmsmanager;

--
-- Name: gw_soft_upgrade_temp_map_log; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_soft_upgrade_temp_map_log (
    temp_id numeric(4,0) NOT NULL,
    devicetype_id_old numeric(20,0) NOT NULL,
    devicetype_id numeric(20,0) NOT NULL,
    operate_time numeric(10,0),
    acc_oid numeric(10,0),
    operate_type numeric(2,0)
);


ALTER TABLE public.gw_soft_upgrade_temp_map_log OWNER TO gtmsmanager;

--
-- Name: gw_strategy_qos; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_strategy_qos (
    id numeric(20,0) NOT NULL,
    tmpl_id numeric(6,0) NOT NULL
);


ALTER TABLE public.gw_strategy_qos OWNER TO gtmsmanager;

--
-- Name: gw_strategy_qos_param; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_strategy_qos_param (
    id numeric(11,0) NOT NULL,
    sub_order numeric(6,0) NOT NULL,
    type_order numeric(6,0) NOT NULL,
    sub_id numeric(6,0) NOT NULL,
    type_id numeric(6,0) NOT NULL,
    type_name character varying(200),
    type_max text,
    type_min text,
    type_prot character varying(200),
    queue_id numeric(1,0),
    para_value text
);


ALTER TABLE public.gw_strategy_qos_param OWNER TO gtmsmanager;

--
-- Name: gw_strategy_qos_tmpl; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_strategy_qos_tmpl (
    id numeric(10,0) NOT NULL,
    tmpl_id numeric(6,0) NOT NULL
);


ALTER TABLE public.gw_strategy_qos_tmpl OWNER TO gtmsmanager;

--
-- Name: gw_strategy_sheet; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_strategy_sheet (
    id numeric(10,0) NOT NULL,
    bss_sheet_id character varying(30) NOT NULL,
    remark character varying(200)
);


ALTER TABLE public.gw_strategy_sheet OWNER TO gtmsmanager;

--
-- Name: gw_strategy_type; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_strategy_type (
    type_id numeric(2,0) NOT NULL,
    type_name character varying(30) NOT NULL,
    type_desc character varying(100)
);


ALTER TABLE public.gw_strategy_type OWNER TO gtmsmanager;

--
-- Name: COLUMN gw_strategy_type.type_name; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_strategy_type.type_name IS '0, 立即执行
1,第一次连到系统''
2,周期上报
3,重启终端
4,下次连接到系统
5,终端启动
';


--
-- Name: gw_subnets; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_subnets (
    id integer NOT NULL,
    grandgroup character varying(15),
    subnetgrp character varying(15) NOT NULL,
    igroupmask numeric(65,0) NOT NULL,
    subnet character varying(15) NOT NULL,
    inetmask numeric(65,0) NOT NULL,
    netmask character varying(15),
    highaddr character varying(15),
    lowaddr character varying(15),
    totaladdr numeric(65,0),
    childcount numeric(65,0),
    assign numeric(65,0),
    mailstatus numeric(65,0) NOT NULL,
    city_id character varying(50),
    subnetcomment character varying(40),
    approve numeric(65,0),
    purpose character varying(4),
    assigntime numeric(10,0),
    fip character varying(12),
    fhighaddress character varying(12),
    flowaddress character varying(12)
);


ALTER TABLE public.gw_subnets OWNER TO gtmsmanager;

--
-- Name: COLUMN gw_subnets.assign; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_subnets.assign IS '分配状态:
0:未分配
1:已分配给地市
3:分配给用户
4:分配给网络
5:等待审批
';


--
-- Name: COLUMN gw_subnets.mailstatus; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_subnets.mailstatus IS '0:等待发信
1:等待回信
2:无需发送
3:注册成功
4:注册失败
5:删除注册成功
6:删除注册失败
';


--
-- Name: COLUMN gw_subnets.approve; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_subnets.approve IS '0：同意
1：不同意
2：未审批
';


--
-- Name: COLUMN gw_subnets.purpose; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_subnets.purpose IS '用途(用户,网络)';


--
-- Name: COLUMN gw_subnets.fip; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_subnets.fip IS '12位的，
如191.23.12.27换为
191023012027
';


--
-- Name: gw_syslog_file; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_syslog_file (
    dir_id numeric(10,0) NOT NULL,
    file_name character varying(100) NOT NULL,
    file_size numeric(10,0),
    file_desc character varying(200),
    device_id character varying(10) NOT NULL,
    "time" numeric(10,0) NOT NULL,
    status numeric(1,0) NOT NULL
);


ALTER TABLE public.gw_syslog_file OWNER TO gtmsmanager;

--
-- Name: gw_tr069; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_tr069 (
    device_id character varying(50) NOT NULL,
    "time" numeric(10,0) NOT NULL,
    url character varying(50),
    peri_inform_enable numeric(1,0) NOT NULL,
    peri_inform_interval numeric(5,0) NOT NULL,
    peri_inform_time character varying(20),
    username character varying(50),
    passwd character varying(50),
    conn_req_username character varying(50),
    conn_req_passwd character varying(50)
);


ALTER TABLE public.gw_tr069 OWNER TO gtmsmanager;

--
-- Name: gw_tr069_bbms; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_tr069_bbms (
    device_id character varying(50) NOT NULL,
    "time" numeric(10,0) NOT NULL,
    url character varying(50),
    peri_inform_enable numeric(1,0) NOT NULL,
    peri_inform_interval numeric(5,0) NOT NULL,
    peri_inform_time character varying(20),
    username character varying(50),
    passwd character varying(50),
    conn_req_username character varying(50),
    conn_req_passwd character varying(50)
);


ALTER TABLE public.gw_tr069_bbms OWNER TO gtmsmanager;

--
-- Name: gw_traceroute; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_traceroute (
    device_id character varying(20),
    "time" numeric(10,0),
    trace_host character varying(100),
    number_of_tries numeric(10,0),
    max_hop_count numeric(10,0),
    data_block_size numeric(10,0),
    time_out numeric(10,0),
    hop_host character varying(100),
    hop_host_address character varying(100),
    hop_error_code character varying(100),
    hop_rt_times character varying(100)
);


ALTER TABLE public.gw_traceroute OWNER TO gtmsmanager;

--
-- Name: gw_user_midware_serv; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_user_midware_serv (
    username character varying(40) NOT NULL,
    serv_type_id numeric(4,0) NOT NULL,
    oper_type_id numeric(4,0) NOT NULL,
    stat numeric(6,0) NOT NULL,
    oper_time numeric(14,0) NOT NULL
);


ALTER TABLE public.gw_user_midware_serv OWNER TO gtmsmanager;

--
-- Name: COLUMN gw_user_midware_serv.stat; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_user_midware_serv.stat IS '指中间件平台返回给ITMS的状态
0：失败
1: 服务器连接失败
>1000:异常';


--
-- Name: gw_usertype_servtype; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_usertype_servtype (
    user_type numeric(4,0) NOT NULL,
    serv_type_id numeric(4,0) NOT NULL
);


ALTER TABLE public.gw_usertype_servtype OWNER TO gtmsmanager;

--
-- Name: gw_version_file_path; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_version_file_path (
    id numeric(5,0) NOT NULL,
    vendor_id character varying(5) NOT NULL,
    softwareversion character varying(100) NOT NULL,
    version_desc character varying(100),
    version_path character varying(100) NOT NULL,
    record_time numeric(10,0),
    update_time numeric(10,0),
    acc_oid numeric(30,0),
    valid numeric(1,0) NOT NULL,
    version_type numeric(2,0),
    issend numeric(1,0),
    is_new numeric(1,0),
    devicetype_id numeric(4,0)
);


ALTER TABLE public.gw_version_file_path OWNER TO gtmsmanager;

--
-- Name: COLUMN gw_version_file_path.version_type; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_version_file_path.version_type IS '1:����������
2:��������������
0������:��������
is_new:��������������������
devicetype_id:����id';


--
-- Name: gw_voip; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_voip (
    device_id character varying(50) NOT NULL,
    voip_id numeric(3,0) NOT NULL,
    gather_time numeric(10,0)
);


ALTER TABLE public.gw_voip OWNER TO gtmsmanager;

--
-- Name: gw_voip_bbms; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_voip_bbms (
    device_id character varying(50) NOT NULL,
    voip_id numeric(3,0) NOT NULL,
    gather_time numeric(10,0)
);


ALTER TABLE public.gw_voip_bbms OWNER TO gtmsmanager;

--
-- Name: gw_voip_digit_device; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_voip_digit_device (
    device_id character varying(10) NOT NULL,
    task_id numeric(10,0) NOT NULL,
    tasktime numeric(10,0) NOT NULL,
    starttime numeric(10,0),
    endtime numeric(10,0),
    map_id numeric(10,0) NOT NULL,
    enable numeric(2,0),
    result_id numeric(6,0)
);


ALTER TABLE public.gw_voip_digit_device OWNER TO gtmsmanager;

--
-- Name: gw_voip_digit_map; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_voip_digit_map (
    map_id numeric(10,0) NOT NULL,
    map_name character varying(100) NOT NULL,
    map_content text NOT NULL,
    acc_oid numeric(10,0),
    city_id character varying(20) NOT NULL,
    upd_time numeric(10,0),
    vendor_id character varying(6),
    device_model_id character varying(4),
    devicetype_id numeric(4,0),
    is_default numeric(1,0)
);


ALTER TABLE public.gw_voip_digit_map OWNER TO gtmsmanager;

--
-- Name: gw_voip_digit_task; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_voip_digit_task (
    task_id numeric(10,0) NOT NULL,
    task_name character varying(100) NOT NULL,
    task_type numeric(5,0) NOT NULL
);


ALTER TABLE public.gw_voip_digit_task OWNER TO gtmsmanager;

--
-- Name: gw_voip_init_param; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_voip_init_param (
    device_id character varying(10) NOT NULL,
    prox_server character varying(20),
    prox_port numeric(10,0),
    prox_server2 character varying(20),
    prox_port2 numeric(10,0),
    regi_serv character varying(20),
    regi_port numeric(10,0),
    stand_regi_serv character varying(20),
    stand_regi_port numeric(10,0),
    out_bound_proxy character varying(20),
    out_bound_port numeric(10,0),
    stand_out_bound_proxy character varying(20),
    stand_out_bound_port numeric(10,0)
);


ALTER TABLE public.gw_voip_init_param OWNER TO gtmsmanager;

--
-- Name: gw_voip_prof; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_voip_prof (
    device_id character varying(50) NOT NULL,
    voip_id numeric(3,0) NOT NULL,
    prof_id numeric(3,0) NOT NULL,
    gather_time numeric(10,0),
    prox_serv character varying(50),
    prox_port numeric(5,0),
    prox_serv_2 character varying(50),
    prox_port_2 numeric(5,0),
    regi_serv character varying(50),
    regi_port numeric(5,0),
    stand_regi_serv character varying(50),
    stand_regi_port numeric(5,0),
    out_bound_proxy character varying(50),
    out_bound_port numeric(5,0),
    stand_out_bound_proxy character varying(50),
    stand_out_bound_port numeric(5,0)
);


ALTER TABLE public.gw_voip_prof OWNER TO gtmsmanager;

--
-- Name: gw_voip_prof_bbms; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_voip_prof_bbms (
    device_id character varying(50) NOT NULL,
    voip_id numeric(3,0) NOT NULL,
    prof_id numeric(3,0) NOT NULL,
    gather_time numeric(10,0),
    prox_serv character varying(50),
    prox_port numeric(5,0),
    prox_serv_2 character varying(50),
    prox_port_2 numeric(5,0),
    regi_serv character varying(50),
    regi_port numeric(5,0),
    stand_regi_serv character varying(50),
    stand_regi_port numeric(5,0),
    out_bound_proxy character varying(50),
    out_bound_port numeric(5,0),
    stand_out_bound_proxy character varying(50),
    stand_out_bound_port numeric(5,0)
);


ALTER TABLE public.gw_voip_prof_bbms OWNER TO gtmsmanager;

--
-- Name: gw_voip_prof_h248; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_voip_prof_h248 (
    device_id character varying(50) NOT NULL,
    voip_id numeric(3,0) NOT NULL,
    prof_id numeric(3,0) NOT NULL,
    gather_time numeric(10,0),
    media_gateway_controler character varying(50),
    media_gateway_controler_port numeric(5,0),
    media_gateway_controler_2 character varying(50),
    media_gateway_controler_port_2 numeric(5,0),
    media_gateway_port numeric(5,0),
    h248_device_id character varying(50),
    h248_device_id_type numeric(5,0),
    rtp_prefix character varying(50),
    pending_timer_init character varying(50),
    retran_interval_timer character varying(50)
);


ALTER TABLE public.gw_voip_prof_h248 OWNER TO gtmsmanager;

--
-- Name: gw_voip_prof_h248_bbms; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_voip_prof_h248_bbms (
    device_id character varying(50) NOT NULL,
    voip_id numeric(3,0) NOT NULL,
    prof_id numeric(3,0) NOT NULL,
    gather_time numeric(10,0),
    media_gateway_controler character varying(50),
    media_gateway_controler_port numeric(5,0),
    media_gateway_controler_2 character varying(50),
    media_gateway_controler_port_2 numeric(5,0),
    media_gateway_port numeric(5,0),
    h248_device_id character varying(50),
    h248_device_id_type numeric(5,0),
    rtp_prefix character varying(50)
);


ALTER TABLE public.gw_voip_prof_h248_bbms OWNER TO gtmsmanager;

--
-- Name: gw_voip_prof_line; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_voip_prof_line (
    device_id character varying(50) NOT NULL,
    voip_id numeric(3,0) NOT NULL,
    prof_id numeric(3,0) NOT NULL,
    line_id numeric(3,0) NOT NULL,
    gather_time numeric(10,0) NOT NULL,
    enable character varying(20),
    status character varying(50),
    username character varying(50),
    password character varying(50),
    regist_result numeric(10,0),
    physical_term_id character varying(50)
);


ALTER TABLE public.gw_voip_prof_line OWNER TO gtmsmanager;

--
-- Name: COLUMN gw_voip_prof_line.enable; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_voip_prof_line.enable IS 'Disabled
Quiescent
Enabled';


--
-- Name: gw_voip_prof_line_bbms; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_voip_prof_line_bbms (
    device_id character varying(50) NOT NULL,
    voip_id numeric(3,0) NOT NULL,
    prof_id numeric(3,0) NOT NULL,
    line_id numeric(3,0) NOT NULL,
    gather_time numeric(10,0) NOT NULL,
    enable character varying(20),
    status character varying(50),
    username character varying(50),
    password character varying(50),
    regist_result numeric(10,0),
    physical_term_id character varying(50)
);


ALTER TABLE public.gw_voip_prof_line_bbms OWNER TO gtmsmanager;

--
-- Name: COLUMN gw_voip_prof_line_bbms.enable; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_voip_prof_line_bbms.enable IS 'Disabled
Quiescent
Enabled';


--
-- Name: gw_wan; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_wan (
    device_id character varying(10) NOT NULL,
    wan_id numeric(2,0) NOT NULL,
    gather_time numeric(10,0) NOT NULL,
    access_type character varying(20) NOT NULL,
    wan_conn_num numeric(3,0)
);


ALTER TABLE public.gw_wan OWNER TO gtmsmanager;

--
-- Name: gw_wan_bbms; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_wan_bbms (
    device_id character varying(10) NOT NULL,
    wan_id numeric(2,0) NOT NULL,
    gather_time numeric(10,0) NOT NULL,
    access_type character varying(20) NOT NULL,
    wan_conn_num numeric(3,0)
);


ALTER TABLE public.gw_wan_bbms OWNER TO gtmsmanager;

--
-- Name: gw_wan_conn; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_wan_conn (
    device_id character varying(10) NOT NULL,
    wan_id numeric(2,0) NOT NULL,
    wan_conn_id numeric(3,0) NOT NULL,
    gather_time numeric(10,0) NOT NULL,
    ip_conn_num numeric(3,0),
    ppp_conn_num numeric(3,0),
    vpi_id character varying(10),
    vci_id numeric(6,0),
    vlan_id character varying(20)
);


ALTER TABLE public.gw_wan_conn OWNER TO gtmsmanager;

--
-- Name: gw_wan_conn_bbms; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_wan_conn_bbms (
    device_id character varying(10) NOT NULL,
    wan_id numeric(2,0) NOT NULL,
    wan_conn_id numeric(3,0) NOT NULL,
    gather_time numeric(10,0) NOT NULL,
    ip_conn_num numeric(3,0),
    ppp_conn_num numeric(3,0),
    vpi_id character varying(10),
    vci_id numeric(6,0),
    vlan_id character varying(20),
    link_status character varying(20)
);


ALTER TABLE public.gw_wan_conn_bbms OWNER TO gtmsmanager;

--
-- Name: gw_wan_conn_history; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_wan_conn_history (
    device_id character varying(10) NOT NULL,
    wan_id numeric(2,0) NOT NULL,
    wan_conn_id numeric(3,0) NOT NULL,
    gather_time numeric(10,0) NOT NULL,
    ip_conn_num numeric(3,0),
    ppp_conn_num numeric(3,0),
    vpi_id character varying(10),
    vci_id numeric(6,0),
    vlan_id character varying(20)
);


ALTER TABLE public.gw_wan_conn_history OWNER TO gtmsmanager;

--
-- Name: gw_wan_conn_namechange; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_wan_conn_namechange (
    device_id character varying(10) NOT NULL,
    wan_id numeric(2,0) NOT NULL,
    wan_conn_id numeric(3,0) NOT NULL,
    vpi_id character varying(10),
    vci_id numeric(6,0),
    vlan_id character varying(20),
    vlan_id_flag character varying(20),
    gather_time numeric(10,0) NOT NULL
);


ALTER TABLE public.gw_wan_conn_namechange OWNER TO gtmsmanager;

--
-- Name: COLUMN gw_wan_conn_namechange.vlan_id_flag; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_wan_conn_namechange.vlan_id_flag IS 'PP:1
IP:2';


--
-- Name: gw_wan_conn_session; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_wan_conn_session (
    device_id character varying(10) NOT NULL,
    wan_id numeric(2,0) NOT NULL,
    wan_conn_id numeric(3,0) NOT NULL,
    wan_conn_sess_id numeric(3,0) NOT NULL,
    sess_type numeric(1,0) NOT NULL,
    gather_time numeric(10,0) NOT NULL,
    enable numeric(1,0) NOT NULL,
    name character varying(50),
    conn_type character varying(20),
    serv_list character varying(20),
    bind_port text,
    username character varying(50),
    password character varying(50),
    ip_type character varying(50),
    ip character varying(50),
    mask character varying(50),
    gateway character varying(50),
    dns_enab numeric(1,0) NOT NULL,
    dns character varying(50),
    cpe_mac character varying(50),
    conn_status character varying(50),
    nat_enab numeric(1,0),
    last_conn_error character varying(50),
    ppp_auth_protocol character varying(50),
    dial_num character varying(50),
    work_mode character varying(50),
    load_percent numeric(10,0),
    backup_itfs character varying(100),
    conn_media character varying(50),
    conn_trigger character varying(50),
    ip_mode character varying(50),
    ip_ipv6 character varying(50),
    dns_ipv6 character varying(50),
    multicast_vlan character varying(50),
    dhcp_enable character varying(2)
);


ALTER TABLE public.gw_wan_conn_session OWNER TO gtmsmanager;

--
-- Name: COLUMN gw_wan_conn_session.sess_type; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_wan_conn_session.sess_type IS '1：PPP
2：IP
';


--
-- Name: COLUMN gw_wan_conn_session.enable; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_wan_conn_session.enable IS 'Enable
1:可用
0:不可用
类型:Boolean
IP,PPP都有此参数
';


--
-- Name: COLUMN gw_wan_conn_session.dns_enab; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_wan_conn_session.dns_enab IS 'DNSEnabled
1:开启
0:未
类型:Boolean
IP,PPP都有此参数
';


--
-- Name: COLUMN gw_wan_conn_session.nat_enab; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_wan_conn_session.nat_enab IS '1:TRUE
0:FALSE';


--
-- Name: gw_wan_conn_session_bbms; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_wan_conn_session_bbms (
    device_id character varying(10) NOT NULL,
    wan_id numeric(2,0) NOT NULL,
    wan_conn_id numeric(3,0) NOT NULL,
    wan_conn_sess_id numeric(3,0) NOT NULL,
    sess_type numeric(1,0) NOT NULL,
    gather_time numeric(10,0) NOT NULL,
    enable numeric(1,0) NOT NULL,
    name character varying(50),
    conn_type character varying(20),
    serv_list character varying(20),
    bind_port text,
    username character varying(50),
    password character varying(50),
    ip_type character varying(50),
    ip character varying(50),
    mask character varying(50),
    gateway character varying(50),
    dns_enab numeric(1,0) NOT NULL,
    dns character varying(50),
    cpe_mac character varying(50),
    conn_status character varying(50),
    nat_enab numeric(1,0),
    last_conn_error character varying(50),
    ppp_auth_protocol character varying(50),
    dial_num character varying(50),
    work_mode character varying(50),
    load_percent numeric(10,0),
    backup_itfs character varying(100),
    conn_media character varying(50),
    conn_trigger character varying(50)
);


ALTER TABLE public.gw_wan_conn_session_bbms OWNER TO gtmsmanager;

--
-- Name: COLUMN gw_wan_conn_session_bbms.sess_type; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_wan_conn_session_bbms.sess_type IS '1：PPP
2：IP
';


--
-- Name: COLUMN gw_wan_conn_session_bbms.enable; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_wan_conn_session_bbms.enable IS 'Enable
1:可用
0:不可用
类型:Boolean
IP,PPP都有此参数
';


--
-- Name: COLUMN gw_wan_conn_session_bbms.dns_enab; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_wan_conn_session_bbms.dns_enab IS 'DNSEnabled
1:开启
0:未
类型:Boolean
IP,PPP都有此参数
';


--
-- Name: COLUMN gw_wan_conn_session_bbms.nat_enab; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_wan_conn_session_bbms.nat_enab IS '1:TRUE
0:FALSE';


--
-- Name: gw_wan_conn_session_history; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_wan_conn_session_history (
    device_id character varying(10) NOT NULL,
    wan_id numeric(2,0) NOT NULL,
    wan_conn_id numeric(3,0) NOT NULL,
    wan_conn_sess_id numeric(3,0) NOT NULL,
    sess_type numeric(1,0) NOT NULL,
    gather_time numeric(10,0) NOT NULL,
    enable numeric(1,0) NOT NULL,
    name character varying(50),
    conn_type character varying(20),
    serv_list character varying(20),
    bind_port text,
    username character varying(50),
    password character varying(50),
    ip_type character varying(50),
    ip character varying(50),
    mask character varying(50),
    gateway character varying(50),
    dns_enab numeric(1,0) NOT NULL,
    dns character varying(50),
    cpe_mac character varying(50),
    conn_status character varying(50),
    nat_enab numeric(1,0),
    last_conn_error character varying(50),
    ppp_auth_protocol character varying(50),
    dial_num character varying(50),
    work_mode character varying(50),
    load_percent numeric(10,0),
    backup_itfs character varying(100),
    conn_media character varying(50),
    conn_trigger character varying(50)
);


ALTER TABLE public.gw_wan_conn_session_history OWNER TO gtmsmanager;

--
-- Name: COLUMN gw_wan_conn_session_history.sess_type; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_wan_conn_session_history.sess_type IS '1��PPP
2��IP
';


--
-- Name: COLUMN gw_wan_conn_session_history.enable; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_wan_conn_session_history.enable IS 'Enable
1:����
0:������
����:Boolean
IP,PPP����������
';


--
-- Name: COLUMN gw_wan_conn_session_history.dns_enab; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_wan_conn_session_history.dns_enab IS 'DNSEnabled
1:����
0:��
����:Boolean
IP,PPP����������
';


--
-- Name: COLUMN gw_wan_conn_session_history.nat_enab; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_wan_conn_session_history.nat_enab IS '1:TRUE
0:FALSE';


--
-- Name: gw_wan_conn_session_namechange; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_wan_conn_session_namechange (
    device_id character varying(10) NOT NULL,
    wan_id numeric(2,0) NOT NULL,
    wan_conn_id numeric(3,0) NOT NULL,
    wan_conn_sess_id numeric(3,0) NOT NULL,
    sess_type numeric(1,0) NOT NULL,
    serv_list character varying(20),
    gather_time numeric(10,0) NOT NULL,
    id numeric(10,0)
);


ALTER TABLE public.gw_wan_conn_session_namechange OWNER TO gtmsmanager;

--
-- Name: gw_wan_conn_session_vpn_bbms; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_wan_conn_session_vpn_bbms (
    device_id character varying(10) NOT NULL,
    wan_id numeric(2,0) NOT NULL,
    wan_conn_id numeric(3,0) NOT NULL,
    wan_conn_sess_id numeric(3,0) NOT NULL,
    sess_type numeric(1,0) NOT NULL,
    wan_conn_sess_vpn_id numeric(2,0) NOT NULL,
    enable numeric(2,0),
    type character varying(20),
    gather_time numeric(10,0)
);


ALTER TABLE public.gw_wan_conn_session_vpn_bbms OWNER TO gtmsmanager;

--
-- Name: gw_wan_dsl_inter_conf_health; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_wan_dsl_inter_conf_health (
    device_id character varying(50) NOT NULL,
    wan_id numeric(3,0) NOT NULL,
    status character varying(30),
    modulation_type character varying(30),
    up_attenuation numeric(10,0),
    up_attenuation_max numeric(10,0),
    up_attenuation_min numeric(10,0),
    down_attenuation numeric(10,0),
    down_attenuation_max numeric(10,0),
    down_attenuation_min numeric(10,0),
    up_maxrate numeric(10,0),
    up_maxrate_max numeric(10,0),
    up_maxrate_min numeric(10,0),
    down_maxrate numeric(10,0),
    down_maxrate_max numeric(10,0),
    down_maxrate_min numeric(10,0),
    data_path character varying(30),
    interleave_depth numeric(10,0),
    interleave_depth_max numeric(10,0),
    interleave_depth_min numeric(10,0),
    update_time numeric(10,0),
    up_noise numeric(10,0),
    up_noise_max numeric(10,0),
    up_noise_min numeric(10,0),
    down_noise numeric(10,0),
    down_noise_max numeric(10,0),
    down_noise_min numeric(10,0)
);


ALTER TABLE public.gw_wan_dsl_inter_conf_health OWNER TO gtmsmanager;

--
-- Name: COLUMN gw_wan_dsl_inter_conf_health.status; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_wan_dsl_inter_conf_health.status IS 'DSL物理链路的状态。枚举值：
"Up"
"Initializing"
"EstablishingLink"
"NoSignal"
"Error"
"Disabled"';


--
-- Name: COLUMN gw_wan_dsl_inter_conf_health.modulation_type; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_wan_dsl_inter_conf_health.modulation_type IS '说明连接所用的调制类型。枚举值：
  “ADSL-G.dmt”
  “ADSL_G.lite”
  “ADSL_G.dmt.bis”
  “ADSL_re-adsl”
  “ADSL_2plus”
  “ADSL_four”
  “ADSL_ANSI_T1.413”
  “G.shdsl”
  “IDSL”
  “HDSL”
  “SDSL”
“VDSL”
';


--
-- Name: COLUMN gw_wan_dsl_inter_conf_health.up_attenuation; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_wan_dsl_inter_conf_health.up_attenuation IS '表示为0.1dB';


--
-- Name: COLUMN gw_wan_dsl_inter_conf_health.up_attenuation_max; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_wan_dsl_inter_conf_health.up_attenuation_max IS '表示为0.1dB';


--
-- Name: COLUMN gw_wan_dsl_inter_conf_health.up_attenuation_min; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_wan_dsl_inter_conf_health.up_attenuation_min IS '表示为0.1dB';


--
-- Name: COLUMN gw_wan_dsl_inter_conf_health.down_attenuation; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_wan_dsl_inter_conf_health.down_attenuation IS '表示为0.1dB';


--
-- Name: COLUMN gw_wan_dsl_inter_conf_health.down_attenuation_max; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_wan_dsl_inter_conf_health.down_attenuation_max IS '表示为0.1dB';


--
-- Name: COLUMN gw_wan_dsl_inter_conf_health.down_attenuation_min; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_wan_dsl_inter_conf_health.down_attenuation_min IS '表示为0.1dB';


--
-- Name: COLUMN gw_wan_dsl_inter_conf_health.up_maxrate; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_wan_dsl_inter_conf_health.up_maxrate IS '上行DSL频道当前可达到的速率（表示为Kbps）';


--
-- Name: COLUMN gw_wan_dsl_inter_conf_health.up_maxrate_max; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_wan_dsl_inter_conf_health.up_maxrate_max IS '上行DSL频道当前可达到的速率（表示为Kbps）';


--
-- Name: COLUMN gw_wan_dsl_inter_conf_health.up_maxrate_min; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_wan_dsl_inter_conf_health.up_maxrate_min IS '上行DSL频道当前可达到的速率（表示为Kbps）';


--
-- Name: COLUMN gw_wan_dsl_inter_conf_health.down_maxrate; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_wan_dsl_inter_conf_health.down_maxrate IS '下行DSL频道当前可达到的速率（表示为Kbps）';


--
-- Name: COLUMN gw_wan_dsl_inter_conf_health.down_maxrate_max; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_wan_dsl_inter_conf_health.down_maxrate_max IS '下行DSL频道当前可达到的速率（表示为Kbps）';


--
-- Name: COLUMN gw_wan_dsl_inter_conf_health.down_maxrate_min; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_wan_dsl_inter_conf_health.down_maxrate_min IS '下行DSL频道当前可达到的速率（表示为Kbps）';


--
-- Name: COLUMN gw_wan_dsl_inter_conf_health.data_path; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_wan_dsl_inter_conf_health.data_path IS '快速Fast
交织Interleave';


--
-- Name: COLUMN gw_wan_dsl_inter_conf_health.interleave_depth; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_wan_dsl_inter_conf_health.interleave_depth IS '该变量只有在DataPath = Interleaved时才使用';


--
-- Name: COLUMN gw_wan_dsl_inter_conf_health.interleave_depth_max; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_wan_dsl_inter_conf_health.interleave_depth_max IS '该变量只有在DataPath = Interleaved时才使用';


--
-- Name: COLUMN gw_wan_dsl_inter_conf_health.interleave_depth_min; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_wan_dsl_inter_conf_health.interleave_depth_min IS '该变量只有在DataPath = Interleaved时才使用';


--
-- Name: gw_wan_history; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_wan_history (
    device_id character varying(10) NOT NULL,
    wan_id numeric(2,0) NOT NULL,
    gather_time numeric(10,0) NOT NULL,
    access_type character varying(20) NOT NULL,
    wan_conn_num numeric(3,0)
);


ALTER TABLE public.gw_wan_history OWNER TO gtmsmanager;

--
-- Name: gw_wan_namechange; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_wan_namechange (
    device_id character varying(10) NOT NULL,
    wan_id numeric(2,0) NOT NULL,
    access_type character varying(20) NOT NULL,
    gather_time numeric(10,0) NOT NULL,
    id numeric(10,0)
);


ALTER TABLE public.gw_wan_namechange OWNER TO gtmsmanager;

--
-- Name: gw_wan_wireinfo; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_wan_wireinfo (
    device_id character varying(10) NOT NULL,
    wan_id numeric(3,0) NOT NULL,
    status character varying(30),
    modulation_type character varying(30),
    up_attenuation numeric(10,0),
    down_attenuation numeric(10,0),
    up_maxrate numeric(10,0),
    down_maxrate numeric(10,0),
    data_path character varying(30),
    interleave_depth numeric(10,0),
    update_time numeric(10,0),
    up_noise numeric(10,0),
    down_noise numeric(10,0)
);


ALTER TABLE public.gw_wan_wireinfo OWNER TO gtmsmanager;

--
-- Name: COLUMN gw_wan_wireinfo.status; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_wan_wireinfo.status IS 'DSL物理链路的状态。枚举值：
"Up"
"Initializing"
"EstablishingLink"
"NoSignal"
"Error"
"Disabled"';


--
-- Name: COLUMN gw_wan_wireinfo.modulation_type; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_wan_wireinfo.modulation_type IS '说明连接所用的调制类型。枚举值：
  “ADSL-G.dmt”
  “ADSL_G.lite”
  “ADSL_G.dmt.bis”
  “ADSL_re-adsl”
  “ADSL_2plus”
  “ADSL_four”
  “ADSL_ANSI_T1.413”
  “G.shdsl”
  “IDSL”
  “HDSL”
  “SDSL”
“VDSL”
';


--
-- Name: COLUMN gw_wan_wireinfo.up_attenuation; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_wan_wireinfo.up_attenuation IS '表示为0.1dB';


--
-- Name: COLUMN gw_wan_wireinfo.down_attenuation; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_wan_wireinfo.down_attenuation IS '表示为0.1dB';


--
-- Name: COLUMN gw_wan_wireinfo.up_maxrate; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_wan_wireinfo.up_maxrate IS '上行DSL频道当前可达到的速率（表示为Kbps）';


--
-- Name: COLUMN gw_wan_wireinfo.down_maxrate; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_wan_wireinfo.down_maxrate IS '下行DSL频道当前可达到的速率（表示为Kbps）';


--
-- Name: COLUMN gw_wan_wireinfo.data_path; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_wan_wireinfo.data_path IS '快速Fast
交织Interleave';


--
-- Name: COLUMN gw_wan_wireinfo.interleave_depth; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_wan_wireinfo.interleave_depth IS '该变量只有在DataPath = Interleaved时才使用';


--
-- Name: gw_wan_wireinfo_bbms; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_wan_wireinfo_bbms (
    device_id character varying(10) NOT NULL,
    wan_id numeric(3,0) NOT NULL,
    status character varying(30),
    modulation_type character varying(30),
    up_attenuation numeric(10,0),
    down_attenuation numeric(10,0),
    up_maxrate numeric(10,0),
    down_maxrate numeric(10,0),
    data_path character varying(30),
    interleave_depth numeric(10,0),
    update_time numeric(10,0),
    up_noise numeric(10,0),
    down_noise numeric(10,0)
);


ALTER TABLE public.gw_wan_wireinfo_bbms OWNER TO gtmsmanager;

--
-- Name: COLUMN gw_wan_wireinfo_bbms.status; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_wan_wireinfo_bbms.status IS 'DSL������������������������
"Up"
"Initializing"
"EstablishingLink"
"NoSignal"
"Error"
"Disabled"';


--
-- Name: COLUMN gw_wan_wireinfo_bbms.modulation_type; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_wan_wireinfo_bbms.modulation_type IS '��������������������������������
  ��ADSL-G.dmt��
  ��ADSL_G.lite��
  ��ADSL_G.dmt.bis��
  ��ADSL_re-adsl��
  ��ADSL_2plus��
  ��ADSL_four��
  ��ADSL_ANSI_T1.413��
  ��G.shdsl��
  ��IDSL��
  ��HDSL��
  ��SDSL��
��VDSL��
';


--
-- Name: COLUMN gw_wan_wireinfo_bbms.up_attenuation; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_wan_wireinfo_bbms.up_attenuation IS '������0.1dB';


--
-- Name: COLUMN gw_wan_wireinfo_bbms.down_attenuation; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_wan_wireinfo_bbms.down_attenuation IS '������0.1dB';


--
-- Name: COLUMN gw_wan_wireinfo_bbms.up_maxrate; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_wan_wireinfo_bbms.up_maxrate IS '����DSL����������������������������Kbps��';


--
-- Name: COLUMN gw_wan_wireinfo_bbms.down_maxrate; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_wan_wireinfo_bbms.down_maxrate IS '����DSL����������������������������Kbps��';


--
-- Name: COLUMN gw_wan_wireinfo_bbms.data_path; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_wan_wireinfo_bbms.data_path IS '����Fast
����Interleave';


--
-- Name: COLUMN gw_wan_wireinfo_bbms.interleave_depth; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_wan_wireinfo_bbms.interleave_depth IS '������������DataPath = Interleaved��������';


--
-- Name: gw_wan_wireinfo_epon; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_wan_wireinfo_epon (
    device_id character varying(10) NOT NULL,
    wan_id numeric(3,0) NOT NULL,
    status character varying(30),
    tx_power character varying(20),
    rx_power character varying(20),
    transceiver_temperature character varying(20),
    supply_vottage character varying(20),
    bias_current character varying(20),
    bytes_sent character varying(20),
    bytes_received character varying(20),
    packets_sent character varying(20),
    packets_received character varying(20),
    sunicast_packets character varying(20),
    runicast_packets character varying(20),
    smulticast_packets character varying(20),
    rmulticast_packets character varying(20),
    sbroadcast_packets character varying(20),
    rbroadcast_packets character varying(20),
    fec_error character varying(20),
    hec_error character varying(20),
    drop_packets character varying(20),
    spause_packets character varying(20),
    rpause_packets character varying(20),
    gather_time numeric(10,0)
);


ALTER TABLE public.gw_wan_wireinfo_epon OWNER TO gtmsmanager;

--
-- Name: COLUMN gw_wan_wireinfo_epon.status; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_wan_wireinfo_epon.status IS 'DSL物理链路的状态。枚举值：
"Up"
"Initializing"
"EstablishingLink"
"NoSignal"
"Error"
"Disabled"';


--
-- Name: COLUMN gw_wan_wireinfo_epon.tx_power; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_wan_wireinfo_epon.tx_power IS '������0.1dB';


--
-- Name: COLUMN gw_wan_wireinfo_epon.rx_power; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_wan_wireinfo_epon.rx_power IS '����DSL����������������������������Kbps��';


--
-- Name: COLUMN gw_wan_wireinfo_epon.bytes_sent; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_wan_wireinfo_epon.bytes_sent IS '下行DSL频道当前可达到的速率（表示为Kbps）';


--
-- Name: COLUMN gw_wan_wireinfo_epon.bytes_received; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_wan_wireinfo_epon.bytes_received IS '快速Fast
交织Interleave';


--
-- Name: COLUMN gw_wan_wireinfo_epon.packets_sent; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_wan_wireinfo_epon.packets_sent IS '该变量只有在DataPath = Interleaved时才使用';


--
-- Name: gw_wan_wireinfo_epon_bbms; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_wan_wireinfo_epon_bbms (
    device_id character varying(10) NOT NULL,
    wan_id numeric(3,0) NOT NULL,
    status character varying(30),
    tx_power character varying(20),
    rx_power character varying(20),
    transceiver_temperature character varying(20),
    supply_vottage character varying(20),
    bias_current character varying(20),
    bytes_sent character varying(20),
    bytes_received character varying(20),
    packets_sent character varying(20),
    packets_received character varying(20),
    sunicast_packets character varying(20),
    runicast_packets character varying(20),
    smulticast_packets character varying(20),
    rmulticast_packets character varying(20),
    sbroadcast_packets character varying(20),
    rbroadcast_packets character varying(20),
    fec_error character varying(20),
    hec_error character varying(20),
    drop_packets character varying(20),
    spause_packets character varying(20),
    rpause_packets character varying(20),
    gather_time numeric(10,0)
);


ALTER TABLE public.gw_wan_wireinfo_epon_bbms OWNER TO gtmsmanager;

--
-- Name: COLUMN gw_wan_wireinfo_epon_bbms.status; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_wan_wireinfo_epon_bbms.status IS 'DSL物理链路的状态。枚举值：
"Up"
"Initializing"
"EstablishingLink"
"NoSignal"
"Error"
"Disabled"';


--
-- Name: COLUMN gw_wan_wireinfo_epon_bbms.tx_power; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_wan_wireinfo_epon_bbms.tx_power IS '表示为0.1dB';


--
-- Name: COLUMN gw_wan_wireinfo_epon_bbms.rx_power; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_wan_wireinfo_epon_bbms.rx_power IS '上行DSL频道当前可达到的速率（表示为Kbps）';


--
-- Name: COLUMN gw_wan_wireinfo_epon_bbms.bytes_sent; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_wan_wireinfo_epon_bbms.bytes_sent IS '下行DSL频道当前可达到的速率（表示为Kbps）';


--
-- Name: COLUMN gw_wan_wireinfo_epon_bbms.bytes_received; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_wan_wireinfo_epon_bbms.bytes_received IS '快速Fast
交织Interleave';


--
-- Name: COLUMN gw_wan_wireinfo_epon_bbms.packets_sent; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_wan_wireinfo_epon_bbms.packets_sent IS '该变量只有在DataPath = Interleaved时才使用';


--
-- Name: gw_wan_wireinfo_epon_history; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_wan_wireinfo_epon_history (
    device_id character varying(10) NOT NULL,
    wan_id numeric(3,0) NOT NULL,
    status character varying(30),
    tx_power character varying(20),
    rx_power character varying(20),
    transceiver_temperature character varying(20),
    supply_vottage character varying(20),
    bias_current character varying(20),
    bytes_sent character varying(20),
    bytes_received character varying(20),
    packets_sent character varying(20),
    packets_received character varying(20),
    sunicast_packets character varying(20),
    runicast_packets character varying(20),
    smulticast_packets character varying(20),
    rmulticast_packets character varying(20),
    sbroadcast_packets character varying(20),
    rbroadcast_packets character varying(20),
    fec_error character varying(20),
    hec_error character varying(20),
    drop_packets character varying(20),
    spause_packets character varying(20),
    rpause_packets character varying(20),
    gather_time numeric(10,0) NOT NULL
);


ALTER TABLE public.gw_wan_wireinfo_epon_history OWNER TO gtmsmanager;

--
-- Name: COLUMN gw_wan_wireinfo_epon_history.status; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_wan_wireinfo_epon_history.status IS 'DSL������������������������
"Up"
"Initializing"
"EstablishingLink"
"NoSignal"
"Error"
"Disabled"';


--
-- Name: COLUMN gw_wan_wireinfo_epon_history.tx_power; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_wan_wireinfo_epon_history.tx_power IS '������0.1dB';


--
-- Name: COLUMN gw_wan_wireinfo_epon_history.rx_power; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_wan_wireinfo_epon_history.rx_power IS '����DSL����������������������������Kbps��';


--
-- Name: COLUMN gw_wan_wireinfo_epon_history.bytes_sent; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_wan_wireinfo_epon_history.bytes_sent IS '����DSL����������������������������Kbps��';


--
-- Name: COLUMN gw_wan_wireinfo_epon_history.bytes_received; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_wan_wireinfo_epon_history.bytes_received IS '����Fast
����Interleave';


--
-- Name: COLUMN gw_wan_wireinfo_epon_history.packets_sent; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_wan_wireinfo_epon_history.packets_sent IS '������������DataPath = Interleaved��������';


--
-- Name: gw_wan_wireinfo_history; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_wan_wireinfo_history (
    device_id character varying(10) NOT NULL,
    wan_id numeric(3,0) NOT NULL,
    status character varying(30),
    modulation_type character varying(30),
    up_attenuation numeric(10,0),
    down_attenuation numeric(10,0),
    up_maxrate numeric(10,0),
    down_maxrate numeric(10,0),
    data_path character varying(30),
    interleave_depth numeric(10,0),
    update_time numeric(10,0),
    up_noise numeric(10,0),
    down_noise numeric(10,0)
);


ALTER TABLE public.gw_wan_wireinfo_history OWNER TO gtmsmanager;

--
-- Name: COLUMN gw_wan_wireinfo_history.status; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_wan_wireinfo_history.status IS 'DSL������������������������
"Up"
"Initializing"
"EstablishingLink"
"NoSignal"
"Error"
"Disabled"';


--
-- Name: COLUMN gw_wan_wireinfo_history.modulation_type; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_wan_wireinfo_history.modulation_type IS '��������������������������������
  ��ADSL-G.dmt��
  ��ADSL_G.lite��
  ��ADSL_G.dmt.bis��
  ��ADSL_re-adsl��
  ��ADSL_2plus��
  ��ADSL_four��
  ��ADSL_ANSI_T1.413��
  ��G.shdsl��
  ��IDSL��
  ��HDSL��
  ��SDSL��
��VDSL��
';


--
-- Name: COLUMN gw_wan_wireinfo_history.up_attenuation; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_wan_wireinfo_history.up_attenuation IS '������0.1dB';


--
-- Name: COLUMN gw_wan_wireinfo_history.down_attenuation; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_wan_wireinfo_history.down_attenuation IS '������0.1dB';


--
-- Name: COLUMN gw_wan_wireinfo_history.up_maxrate; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_wan_wireinfo_history.up_maxrate IS '����DSL����������������������������Kbps��';


--
-- Name: COLUMN gw_wan_wireinfo_history.down_maxrate; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_wan_wireinfo_history.down_maxrate IS '����DSL����������������������������Kbps��';


--
-- Name: COLUMN gw_wan_wireinfo_history.data_path; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_wan_wireinfo_history.data_path IS '����Fast
����Interleave';


--
-- Name: COLUMN gw_wan_wireinfo_history.interleave_depth; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.gw_wan_wireinfo_history.interleave_depth IS '������������DataPath = Interleaved��������';


--
-- Name: gw_wlan_asso; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_wlan_asso (
    device_id character varying(10) NOT NULL,
    lan_id numeric(2,0) NOT NULL,
    lan_wlan_id numeric(3,0) NOT NULL,
    asso_id numeric(3,0) NOT NULL,
    ip_address character varying(15),
    mac_address character varying(50),
    auth_state numeric(1,0)
);


ALTER TABLE public.gw_wlan_asso OWNER TO gtmsmanager;

--
-- Name: gw_wlan_asso_bbms; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.gw_wlan_asso_bbms (
    device_id character varying(10) NOT NULL,
    lan_id numeric(2,0) NOT NULL,
    lan_wlan_id numeric(3,0) NOT NULL,
    asso_id numeric(3,0) NOT NULL,
    ip_address character varying(15),
    mac_address character varying(50),
    auth_state numeric(1,0)
);


ALTER TABLE public.gw_wlan_asso_bbms OWNER TO gtmsmanager;

--
-- Name: hgw_item_role; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.hgw_item_role (
    sequence numeric(6,0),
    item_id character varying(36) NOT NULL,
    role_id numeric(3,0) NOT NULL
);


ALTER TABLE public.hgw_item_role OWNER TO gtmsmanager;

--
-- Name: hgwcust_serv_info; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.hgwcust_serv_info (
    user_id numeric(10,0) NOT NULL,
    serv_type_id numeric(4,0) NOT NULL,
    username character varying(256),
    orderid character varying(50),
    serv_status numeric(1,0) DEFAULT 1 NOT NULL,
    passwd character varying(128),
    wan_type numeric(2,0) DEFAULT 1 NOT NULL,
    vpiid character varying(50),
    vciid numeric(6,0),
    vlanid character varying(50),
    ipaddress character varying(15),
    ipmask character varying(15),
    gateway character varying(15),
    adsl_ser character varying(128),
    bind_port text,
    wan_value_1 character varying(200) DEFAULT '-1'::character varying NOT NULL,
    wan_value_2 character varying(200) DEFAULT '-1'::character varying NOT NULL,
    open_status numeric(1,0) DEFAULT 0 NOT NULL,
    dealdate numeric(10,0),
    opendate numeric(10,0),
    pausedate numeric(10,0),
    closedate numeric(10,0),
    updatetime numeric(10,0),
    completedate numeric(10,0),
    serv_num numeric(3,0),
    multicast_vlanid character varying(20),
    ip_type numeric(2,0) DEFAULT 0 NOT NULL,
    dslite_enable numeric(2,0) DEFAULT 0 NOT NULL,
    real_bind_port text,
    sy_vendor numeric(2,0) DEFAULT 0 NOT NULL,
    real_type_id numeric(4,0) DEFAULT 10 NOT NULL,
    aftr_mode numeric(2,0),
    aftr_ip character varying(40),
    ipv6_address_origin character varying(20),
    ipv6_address character varying(40),
    ipv6_dns character varying(40),
    ipv6_prefix_origin character varying(40),
    ipv6_prefix character varying(40),
    oltfactory character varying(25),
    snoopingeable character varying(10),
    multiplex_lan_port character varying(50),
    order_no character varying(50)
);


ALTER TABLE public.hgwcust_serv_info OWNER TO gtmsmanager;

--
-- Name: COLUMN hgwcust_serv_info.serv_status; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.hgwcust_serv_info.serv_status IS '1:开通
2:暂停
3:销户
';


--
-- Name: COLUMN hgwcust_serv_info.wan_type; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.hgwcust_serv_info.wan_type IS '1:PPPoE(桥接)
2:PPPoE(路由)
3:STATIC
4:DHCP
';


--
-- Name: COLUMN hgwcust_serv_info.bind_port; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.hgwcust_serv_info.bind_port IS '配置设备时要转换
LAN1
LAN2
LAN3
LAN4
WLAN1
WLAN2
WLAN3
WLAN4
';


--
-- Name: COLUMN hgwcust_serv_info.open_status; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.hgwcust_serv_info.open_status IS '0：未做
1：成功
-1:失败
';


--
-- Name: COLUMN hgwcust_serv_info.sy_vendor; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.hgwcust_serv_info.sy_vendor IS '����������1,2,3,4,
����������5';


--
-- Name: COLUMN hgwcust_serv_info.real_type_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.hgwcust_serv_info.real_type_id IS '����������������������';


--
-- Name: itms_bssuser_info; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.itms_bssuser_info (
    user_id character varying(255) NOT NULL,
    city_code character varying(11) NOT NULL,
    prov_code character varying(11) NOT NULL,
    "time" timestamp without time zone,
    account character varying(255),
    address character varying(255),
    contact character varying(255),
    contact_phone character varying(255),
    detail character varying(255),
    loid character varying(255),
    series_number character varying(255),
    tape_width numeric(11,0),
    user_level numeric(11,0),
    user_name character varying(255),
    user_type character varying(255)
);


ALTER TABLE public.itms_bssuser_info OWNER TO gtmsmanager;

--
-- Name: itv_bss_dev_type; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.itv_bss_dev_type (
    type_id character varying(10) NOT NULL,
    type_name character varying(50) NOT NULL,
    type_desc character varying(100)
);


ALTER TABLE public.itv_bss_dev_type OWNER TO gtmsmanager;

--
-- Name: itv_customer_info; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.itv_customer_info (
    id numeric(65,30) NOT NULL,
    customer_id character varying(30) NOT NULL,
    customer_name character varying(100) NOT NULL,
    username character varying(40) NOT NULL,
    serv_status numeric(1,0) NOT NULL,
    city_id character varying(20) NOT NULL,
    prod_spec_id character varying(2) NOT NULL,
    type_id character varying(10),
    serv_package_id character varying(10),
    vpiid character varying(50),
    vciid numeric(6,0),
    vlanid character varying(50),
    reform_flag numeric(1,0) NOT NULL,
    assess_flag numeric(1,0) NOT NULL,
    radius_onlinedate numeric(10,0),
    completedate numeric(10,0),
    bas_ip character varying(160),
    stb_mac character varying(50),
    data_from numeric(2,0) NOT NULL,
    dealdate numeric(10,0),
    opendate numeric(10,0),
    pausedate numeric(10,0),
    closedate numeric(10,0),
    updatetime numeric(10,0),
    forbid_net numeric(1,0),
    dslam_model_id character varying(50)
);


ALTER TABLE public.itv_customer_info OWNER TO gtmsmanager;

--
-- Name: COLUMN itv_customer_info.serv_status; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.itv_customer_info.serv_status IS '1 生效
';


--
-- Name: COLUMN itv_customer_info.prod_spec_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.itv_customer_info.prod_spec_id IS ' 9        ADSL
10        LAN
11        光纤宽带
12        专线ADSL
13        专线LAN
14        专线光纤宽带';


--
-- Name: COLUMN itv_customer_info.reform_flag; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.itv_customer_info.reform_flag IS '1 改造
0 改造';


--
-- Name: COLUMN itv_customer_info.assess_flag; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.itv_customer_info.assess_flag IS '0 否
1 尊享';


--
-- Name: COLUMN itv_customer_info.data_from; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.itv_customer_info.data_from IS '1 bss同步
2 raidus同步';


--
-- Name: COLUMN itv_customer_info.forbid_net; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.itv_customer_info.forbid_net IS '0 未开启
1 开启';


--
-- Name: itv_prod_spec; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.itv_prod_spec (
    prod_spec_id character varying(2) NOT NULL,
    prod_spec_name character varying(50) NOT NULL,
    prod_spec_desc character varying(100)
);


ALTER TABLE public.itv_prod_spec OWNER TO gtmsmanager;

--
-- Name: itv_serv_package; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.itv_serv_package (
    serv_package_id character varying(10) NOT NULL,
    serv_package_name character varying(50) NOT NULL,
    serv_package_desc character varying(100)
);


ALTER TABLE public.itv_serv_package OWNER TO gtmsmanager;

--
-- Name: log_gtms_service; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.log_gtms_service (
    serv_id numeric(10,0) NOT NULL,
    itfs_id character varying(50) NOT NULL,
    client_type_id numeric(3,0) NOT NULL,
    cmd_name character varying(64) NOT NULL,
    username character varying(40),
    device_sn character varying(64),
    city_id character varying(10),
    resp_code numeric(4,0),
    req_info text,
    resp_info text,
    itfs_time numeric(10,0) NOT NULL
);


ALTER TABLE public.log_gtms_service OWNER TO gtmsmanager;

--
-- Name: oss_file; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.oss_file (
    id character varying(32) NOT NULL,
    file_name character varying(255),
    url character varying(255),
    create_by character varying(32),
    create_time timestamp without time zone,
    update_by character varying(32),
    update_time timestamp without time zone
);


ALTER TABLE public.oss_file OWNER TO gtmsmanager;

--
-- Name: TABLE oss_file; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON TABLE public.oss_file IS 'Oss File';


--
-- Name: COLUMN oss_file.id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.oss_file.id IS '主键id';


--
-- Name: COLUMN oss_file.file_name; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.oss_file.file_name IS '文件名称';


--
-- Name: COLUMN oss_file.url; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.oss_file.url IS '文件地址';


--
-- Name: COLUMN oss_file.create_by; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.oss_file.create_by IS '创建人登录名称';


--
-- Name: COLUMN oss_file.create_time; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.oss_file.create_time IS '创建日期';


--
-- Name: COLUMN oss_file.update_by; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.oss_file.update_by IS '更新人登录名称';


--
-- Name: COLUMN oss_file.update_time; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.oss_file.update_time IS '更新日期';


--
-- Name: poor_quality_device_restart; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.poor_quality_device_restart (
    username character varying(40) NOT NULL,
    device_id character varying(10) NOT NULL,
    file_name character varying(50) NOT NULL,
    rlabel character varying(50) NOT NULL,
    status numeric(1,0) NOT NULL,
    add_time numeric(10,0),
    restart_time numeric(10,0)
);


ALTER TABLE public.poor_quality_device_restart OWNER TO gtmsmanager;

--
-- Name: COLUMN poor_quality_device_restart.username; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.poor_quality_device_restart.username IS '宽带账号';


--
-- Name: COLUMN poor_quality_device_restart.device_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.poor_quality_device_restart.device_id IS '设备ID';


--
-- Name: COLUMN poor_quality_device_restart.file_name; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.poor_quality_device_restart.file_name IS '文件名称，从哪个txt文件获取到的数据';


--
-- Name: COLUMN poor_quality_device_restart.rlabel; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.poor_quality_device_restart.rlabel IS '排障标签，多个用逗号分隔';


--
-- Name: COLUMN poor_quality_device_restart.status; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.poor_quality_device_restart.status IS '状态，未重启:0； 重启成功:1； 重启失败：-1；';


--
-- Name: COLUMN poor_quality_device_restart.add_time; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.poor_quality_device_restart.add_time IS '定制时间，批量入表时间';


--
-- Name: COLUMN poor_quality_device_restart.restart_time; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.poor_quality_device_restart.restart_time IS '重启的时间';


--
-- Name: pp_itfs_data; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.pp_itfs_data (
    pp_id numeric(10,0) NOT NULL,
    pp_type numeric(1,0),
    "time" numeric(10,0),
    device_id character varying(50),
    strategy_id numeric(10,0),
    conf_id numeric(4,0),
    user_id numeric(10,0),
    gather_id character varying(10),
    oui character varying(6),
    dev_sn character varying(64),
    serv_type_id numeric(4,0),
    oper_type_id numeric(4,0),
    is_new numeric(1,0),
    data_card_id numeric(10,0),
    data_card_sn character varying(50),
    uim_card_id numeric(10,0),
    uim_card_sn character varying(50)
);


ALTER TABLE public.pp_itfs_data OWNER TO gtmsmanager;

--
-- Name: COLUMN pp_itfs_data.pp_type; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.pp_itfs_data.pp_type IS '1：默认业务
2：绑定下发业务
3：只下发业务
4：EVDO';


--
-- Name: sgw_model_security_template; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.sgw_model_security_template (
    template_id numeric(10,0) NOT NULL,
    device_model_id character varying(4) NOT NULL,
    snmp_version character varying(5) NOT NULL,
    is_enable numeric(1,0) NOT NULL,
    security_username character varying(30),
    security_model numeric(10,0),
    engine_id character varying(30),
    context_name character varying(100),
    security_level numeric(1,0),
    auth_protocol character varying(30),
    auth_passwd character varying(30),
    privacy_protocol character varying(30),
    privacy_passwd character varying(30),
    snmp_r_passwd character varying(30),
    snmp_w_passwd character varying(30)
);


ALTER TABLE public.sgw_model_security_template OWNER TO gtmsmanager;

--
-- Name: COLUMN sgw_model_security_template.device_model_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sgw_model_security_template.device_model_id IS '对应设备型号
0为所有型号默认。
即若无此型号对应的模板，则型号用0取代
';


--
-- Name: COLUMN sgw_model_security_template.snmp_version; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sgw_model_security_template.snmp_version IS 'v1,v2,v3';


--
-- Name: COLUMN sgw_model_security_template.is_enable; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sgw_model_security_template.is_enable IS '1: 启用
0: 不启用
';


--
-- Name: COLUMN sgw_model_security_template.security_model; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sgw_model_security_template.security_model IS '0:不标识安全模型；
1—255:保留给IANA；
>255:分配给各个企业安全模型
';


--
-- Name: COLUMN sgw_model_security_template.security_level; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sgw_model_security_template.security_level IS '1:noAuthNoPriv，2:AuthNoPriv，
3:AuthPriv
';


--
-- Name: COLUMN sgw_model_security_template.auth_protocol; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sgw_model_security_template.auth_protocol IS '鉴别模式:
MD5
SHA-1
';


--
-- Name: COLUMN sgw_model_security_template.privacy_protocol; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sgw_model_security_template.privacy_protocol IS '加解密协议：DES、IDEA、AES128、AES192、AES256';


--
-- Name: sgw_security; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.sgw_security (
    device_id character varying(10) NOT NULL,
    snmp_version character varying(5) NOT NULL,
    is_enable numeric(1,0) NOT NULL,
    security_username character varying(30),
    security_model numeric(10,0),
    engine_id character varying(30),
    context_name character varying(100),
    security_level numeric(1,0),
    auth_protocol character varying(30),
    auth_passwd character varying(30),
    privacy_protocol character varying(30),
    privacy_passwd character varying(30),
    snmp_r_passwd character varying(30),
    snmp_w_passwd character varying(30)
);


ALTER TABLE public.sgw_security OWNER TO gtmsmanager;

--
-- Name: COLUMN sgw_security.device_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sgw_security.device_id IS '外健
tab_gw_device(device_id)
';


--
-- Name: COLUMN sgw_security.is_enable; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sgw_security.is_enable IS '1: 启用
0: 不启用
';


--
-- Name: COLUMN sgw_security.security_model; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sgw_security.security_model IS '0:不标识安全模型；
1—255:保留给IANA；
>255:分配给各个企业安全模型
';


--
-- Name: COLUMN sgw_security.security_level; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sgw_security.security_level IS '1:noAuthNoPriv，2:AuthNoPriv，
3:AuthPriv
';


--
-- Name: COLUMN sgw_security.auth_protocol; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sgw_security.auth_protocol IS '鉴别模式:
MD5
SHA-1
';


--
-- Name: COLUMN sgw_security.privacy_protocol; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sgw_security.privacy_protocol IS '加解密协议：DES、IDEA、AES128、AES192、AES256';


--
-- Name: sql_gw_serv_strategy; Type: SEQUENCE; Schema: public; Owner: gtmsmanager
--

CREATE SEQUENCE public.sql_gw_serv_strategy
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.sql_gw_serv_strategy OWNER TO gtmsmanager;

--
-- Name: stb_gw_device_model; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.stb_gw_device_model (
    device_model_id character varying(4) NOT NULL,
    vendor_id character varying(6) NOT NULL,
    device_model character varying(64) NOT NULL,
    prot_id numeric(1,0) DEFAULT 1 NOT NULL,
    add_time numeric(10,0)
);


ALTER TABLE public.stb_gw_device_model OWNER TO gtmsmanager;

--
-- Name: COLUMN stb_gw_device_model.add_time; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.stb_gw_device_model.add_time IS '秒';


--
-- Name: stb_gw_devicestatus; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.stb_gw_devicestatus (
    device_id character varying(10) NOT NULL,
    online_status numeric(1,0) DEFAULT 1 NOT NULL,
    last_time numeric(10,0) DEFAULT 0 NOT NULL,
    oper_time numeric(10,0) DEFAULT 0,
    bind_log_stat numeric(2,0) DEFAULT '-1'::integer NOT NULL,
    reboot_time numeric(10,0)
);


ALTER TABLE public.stb_gw_devicestatus OWNER TO gtmsmanager;

--
-- Name: COLUMN stb_gw_devicestatus.device_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.stb_gw_devicestatus.device_id IS '外键:stb_gw_device(device_id)';


--
-- Name: COLUMN stb_gw_devicestatus.online_status; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.stb_gw_devicestatus.online_status IS '1:在线，0:不在线';


--
-- Name: COLUMN stb_gw_devicestatus.bind_log_stat; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.stb_gw_devicestatus.bind_log_stat IS '-1:默认，1:BIND1，2:BIND2';


--
-- Name: stb_gw_filepath_devtype; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.stb_gw_filepath_devtype (
    path_id numeric(5,0) NOT NULL,
    vendor_id character varying(6) NOT NULL,
    device_model_id character varying(4) NOT NULL,
    goal_devicetype_id numeric(4,0) NOT NULL
);


ALTER TABLE public.stb_gw_filepath_devtype OWNER TO gtmsmanager;

--
-- Name: stb_gw_serv_strategy; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.stb_gw_serv_strategy (
    id numeric(11,0) NOT NULL,
    status numeric(10,0) DEFAULT 0 NOT NULL,
    result_id numeric(6,0) DEFAULT 0 NOT NULL,
    result_desc character varying(200),
    acc_oid character varying(10) DEFAULT 1 NOT NULL,
    "time" numeric(10,0) NOT NULL,
    start_time numeric(10,0),
    end_time numeric(10,0),
    type numeric(1,0) DEFAULT 0 NOT NULL,
    gather_id character varying(100),
    device_id character varying(100),
    oui character varying(6),
    device_serialnumber character varying(64),
    username character varying(100),
    sheet_id character varying(100),
    sheet_para text,
    service_id numeric(4,0) NOT NULL,
    task_id character varying(15),
    order_id numeric(4,0),
    exec_count numeric(2,0) DEFAULT 0,
    redo numeric(2,0) DEFAULT 0 NOT NULL,
    sheet_type numeric(1,0) DEFAULT 1,
    temp_id numeric(4,0),
    is_last_one numeric(1,0),
    priority numeric(1,0),
    sub_service_id numeric(10,0),
    line_id numeric(10,0),
    client_id numeric,
    ids_task_id numeric
);


ALTER TABLE public.stb_gw_serv_strategy OWNER TO gtmsmanager;

--
-- Name: COLUMN stb_gw_serv_strategy.sheet_type; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.stb_gw_serv_strategy.sheet_type IS '1：老工单，2：新工单';


--
-- Name: stb_gw_serv_strategy_batch; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.stb_gw_serv_strategy_batch (
    id numeric(11,0) NOT NULL,
    status numeric(10,0) DEFAULT 0 NOT NULL,
    result_id numeric(6,0) DEFAULT 0 NOT NULL,
    result_desc text,
    acc_oid character varying(10) DEFAULT 1 NOT NULL,
    "time" numeric(10,0) NOT NULL,
    start_time numeric(10,0),
    end_time numeric(10,0),
    type numeric(10,0) DEFAULT 0 NOT NULL,
    gather_id character varying(100),
    device_id character varying(10),
    oui character varying(6),
    device_serialnumber character varying(64),
    username character varying(100),
    sheet_id character varying(100),
    sheet_para text,
    service_id numeric(4,0) NOT NULL,
    task_id character varying(15),
    order_id numeric(4,0),
    exec_count numeric(2,0) DEFAULT 0,
    redo numeric(2,0) DEFAULT 0 NOT NULL,
    sheet_type numeric(1,0) DEFAULT 1,
    temp_id numeric(4,0),
    is_last_one numeric(1,0),
    priority numeric(1,0) DEFAULT 1,
    sub_service_id numeric(4,0),
    line_id numeric(10,0),
    client_id numeric(10,0),
    ids_task_id numeric(20,0)
);


ALTER TABLE public.stb_gw_serv_strategy_batch OWNER TO gtmsmanager;

--
-- Name: stb_gw_serv_strategy_batch_log; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.stb_gw_serv_strategy_batch_log (
    id numeric(11,0) NOT NULL,
    status numeric(10,0) DEFAULT 0 NOT NULL,
    result_id numeric(6,0) DEFAULT 0 NOT NULL,
    result_desc text,
    acc_oid character varying(10) DEFAULT 1 NOT NULL,
    "time" numeric(10,0) NOT NULL,
    start_time numeric(10,0),
    end_time numeric(10,0),
    type numeric(10,0) DEFAULT 0 NOT NULL,
    gather_id character varying(100),
    device_id character varying(10),
    oui character varying(6),
    device_serialnumber character varying(64),
    username character varying(100),
    sheet_id character varying(100),
    sheet_para text,
    service_id numeric(4,0) NOT NULL,
    task_id character varying(15),
    order_id numeric(4,0),
    exec_count numeric(2,0) DEFAULT 0,
    redo numeric(2,0) DEFAULT 0 NOT NULL,
    sheet_type numeric(1,0) DEFAULT 1,
    temp_id numeric(4,0),
    is_last_one numeric(1,0),
    priority numeric(1,0),
    sub_service_id numeric(4,0),
    line_id numeric(10,0),
    client_id numeric(10,0),
    ids_task_id numeric(20,0)
);


ALTER TABLE public.stb_gw_serv_strategy_batch_log OWNER TO gtmsmanager;

--
-- Name: stb_gw_serv_strategy_log; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.stb_gw_serv_strategy_log (
    id numeric(11,0) NOT NULL,
    status numeric(10,0) DEFAULT 0 NOT NULL,
    result_id numeric(6,0) DEFAULT 0 NOT NULL,
    result_desc character varying(200),
    acc_oid character varying(10) DEFAULT 1 NOT NULL,
    "time" numeric(10,0) NOT NULL,
    start_time numeric(10,0),
    end_time numeric(10,0),
    type numeric(1,0) DEFAULT 0 NOT NULL,
    gather_id character varying(100),
    device_id character varying(100),
    oui character varying(6),
    device_serialnumber character varying(64),
    username character varying(100),
    sheet_id character varying(100),
    sheet_para text,
    service_id numeric(4,0) NOT NULL,
    task_id character varying(15),
    order_id numeric(4,0),
    exec_count numeric(2,0) DEFAULT 0,
    redo numeric(2,0) DEFAULT 0 NOT NULL,
    sheet_type numeric(1,0) DEFAULT 1,
    temp_id numeric(4,0),
    is_last_one numeric(1,0),
    priority numeric(1,0),
    sub_service_id numeric(10,0),
    line_id numeric(10,0),
    client_id numeric,
    ids_task_id numeric
);


ALTER TABLE public.stb_gw_serv_strategy_log OWNER TO gtmsmanager;

--
-- Name: COLUMN stb_gw_serv_strategy_log.sheet_type; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.stb_gw_serv_strategy_log.sheet_type IS '1：老工单，2：新工单';


--
-- Name: stb_gw_soft_upgrade_temp_map; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.stb_gw_soft_upgrade_temp_map (
    temp_id numeric(4,0) NOT NULL,
    devicetype_id_old numeric(4,0) NOT NULL,
    devicetype_id_new numeric(4,0) NOT NULL,
    belong character varying(2) NOT NULL
);


ALTER TABLE public.stb_gw_soft_upgrade_temp_map OWNER TO gtmsmanager;

--
-- Name: stb_tab_boot_event; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.stb_tab_boot_event (
    device_id character varying(32) NOT NULL,
    deal_time numeric(10,0) NOT NULL,
    event_code character varying(32) NOT NULL
);


ALTER TABLE public.stb_tab_boot_event OWNER TO gtmsmanager;

--
-- Name: stb_tab_boot_event_tmp; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.stb_tab_boot_event_tmp (
    device_id character varying(32) NOT NULL,
    deal_time numeric(10,0) NOT NULL,
    event_code character varying(32) NOT NULL
);


ALTER TABLE public.stb_tab_boot_event_tmp OWNER TO gtmsmanager;

--
-- Name: stb_tab_customer; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.stb_tab_customer (
    customer_id numeric(10,0) NOT NULL,
    cust_name character varying(100),
    cust_stat character varying(2) DEFAULT '1'::character varying NOT NULL,
    cust_account character varying(50),
    serv_account character varying(50),
    serv_pwd character varying(50),
    product character varying(255),
    speed numeric(10,0),
    phone_number character varying(50),
    cust_access_type numeric(2,0),
    access_devid character varying(10),
    access_deviceip character varying(50),
    access_deviceport character varying(50),
    vlan_id character varying(50),
    vpi character varying(50),
    vci character varying(50),
    bas_devid character varying(10),
    basip character varying(16),
    net_type numeric(2,0),
    itvport_attr character varying(255),
    city_id character varying(50) DEFAULT '0'::character varying,
    cust_addr text,
    user_type_id character varying(1) DEFAULT '0'::character varying,
    opendate numeric(10,0),
    pausedate numeric(10,0),
    closedate numeric(10,0),
    updatetime numeric(10,0),
    prod_id character varying(20),
    account_type numeric(2,0),
    user_status numeric(2,0),
    belong character varying(2),
    user_grp character varying(50),
    activdate numeric(10,0),
    openuserdate numeric(10,0),
    active_status character varying(10),
    addressing_type character varying(10),
    pppoe_user character varying(50),
    pppoe_pwd text,
    sn character varying(64),
    bss_prod_id character varying(20),
    enterprise_id character varying(100),
    auth_url character varying(200),
    upgrade_url character varying(200),
    ntp_url character varying(200),
    platform character varying(20),
    ipaddress character varying(15),
    ipmap character varying(15),
    gateway character varying(15),
    ipmask character varying(32),
    dns character varying(15),
    cpe_mac character varying(64),
    server_url character varying(255),
    browser_url1 character varying(255),
    browser_url2 character varying(255),
    stbuptyle numeric(2,0),
    loid character varying(40),
    is_prepay character varying(2) DEFAULT '0'::character varying NOT NULL,
    serial_no character varying(64),
    ntp_server1 character varying(25),
    ntp_server2 character varying(25),
    is_merge character varying(1),
    ipoe_user character varying(50),
    ipoe_pwd text,
    is_tel_dev character varying(2)
);


ALTER TABLE public.stb_tab_customer OWNER TO gtmsmanager;

--
-- Name: stb_tab_device_addressinfo; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.stb_tab_device_addressinfo (
    device_id character varying(50) NOT NULL,
    manage_type numeric(2,0) NOT NULL,
    device_ip character varying(50),
    device_port numeric(10,0),
    stun_gid numeric(2,0),
    stun_ip character varying(50),
    stun_port numeric(10,0),
    socket_ip character varying(50),
    socket_port numeric(10,0)
);


ALTER TABLE public.stb_tab_device_addressinfo OWNER TO gtmsmanager;

--
-- Name: stb_tab_devicetype_info; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.stb_tab_devicetype_info (
    devicetype_id numeric(10,0) NOT NULL,
    vendor_id character varying(6) NOT NULL,
    device_model_id character varying(4) NOT NULL,
    specversion character varying(30),
    hardwareversion character varying(30),
    softwareversion character varying(50) NOT NULL,
    area_id numeric(10,0),
    prot_id numeric(1,0) DEFAULT 1 NOT NULL,
    add_time numeric(10,0),
    is_zero numeric(2,0),
    zeroconf character varying(1) DEFAULT '1'::character varying,
    bootadv character varying(1) DEFAULT '1'::character varying,
    category numeric(2,0),
    is_check numeric(2,0) DEFAULT '-1'::integer,
    rela_dev_type_id character varying(100)
);


ALTER TABLE public.stb_tab_devicetype_info OWNER TO gtmsmanager;

--
-- Name: COLUMN stb_tab_devicetype_info.add_time; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.stb_tab_devicetype_info.add_time IS 'category 机顶盒类型：1,4k 2,高清 3,标清 4,融合';


--
-- Name: stb_tab_gw_device; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.stb_tab_gw_device (
    device_id character varying(50) NOT NULL,
    oui character varying(6) NOT NULL,
    device_serialnumber character varying(64) NOT NULL,
    device_name character varying(80),
    city_id character varying(20) DEFAULT '0'::character varying,
    office_id character varying(20) DEFAULT '0'::character varying,
    zone_id character varying(20) DEFAULT '0'::character varying,
    complete_time numeric(10,0),
    buy_time numeric(10,0) DEFAULT 0,
    staff_id character varying(30),
    remark character varying(100),
    loopback_ip character varying(30),
    interface_id numeric(10,0) DEFAULT 0,
    device_status numeric(1,0) DEFAULT 0 NOT NULL,
    gather_id character varying(30) NOT NULL,
    devicetype_id numeric(4,0),
    maxenvelopes numeric(4,0) DEFAULT 1,
    cr_port numeric(10,0) NOT NULL,
    cr_path character varying(30),
    cpe_mac character varying(30),
    cpe_currentupdatetime numeric(10,0),
    cpe_allocatedstatus numeric(1,0) DEFAULT 0,
    cpe_username character varying(50) DEFAULT 'hgw'::character varying,
    cpe_passwd character varying(50) DEFAULT 'hgw'::character varying,
    acs_username character varying(50) DEFAULT 'itms'::character varying,
    acs_passwd character varying(50) DEFAULT 'itms'::character varying,
    device_type character varying(50) DEFAULT 'e8-b'::character varying,
    x_com_username character varying(50) DEFAULT 'telecomadmin'::character varying NOT NULL,
    x_com_passwd character varying(50) DEFAULT 'nE7jA%5m'::character varying NOT NULL,
    gw_type numeric(1,0) DEFAULT 1,
    device_model_id character varying(4),
    customer_id numeric(10,0),
    device_url character varying(200),
    x_com_passwd_old character varying(50) DEFAULT 'nE7jA%5m'::character varying NOT NULL,
    vendor_id character varying(6) NOT NULL,
    bind_time numeric(10,0),
    dev_sub_sn character varying(6) NOT NULL,
    inform_stat numeric(1,0) DEFAULT 1 NOT NULL,
    serv_account character varying(50),
    status numeric(2,0),
    is_zero_version numeric(2,0),
    zero_account character varying(50)
);


ALTER TABLE public.stb_tab_gw_device OWNER TO gtmsmanager;

--
-- Name: stb_tab_gw_device_init_oui; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.stb_tab_gw_device_init_oui (
    id numeric(10,0) NOT NULL,
    oui character varying(50) NOT NULL,
    vendor_add character varying(50) NOT NULL,
    remark character varying(100),
    add_date numeric(10,0),
    vendor_name character varying(50)
);


ALTER TABLE public.stb_tab_gw_device_init_oui OWNER TO gtmsmanager;

--
-- Name: stb_tab_seniorquery_tmp; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.stb_tab_seniorquery_tmp (
    filename character varying(50) NOT NULL,
    username character varying(50),
    devicesn character varying(50)
);


ALTER TABLE public.stb_tab_seniorquery_tmp OWNER TO gtmsmanager;

--
-- Name: stb_tab_setparamvalue_tmp; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.stb_tab_setparamvalue_tmp (
    device_id character varying(10) NOT NULL,
    updatetime numeric(10,0) NOT NULL,
    status numeric(2,0) NOT NULL,
    device_model numeric(2,0)
);


ALTER TABLE public.stb_tab_setparamvalue_tmp OWNER TO gtmsmanager;

--
-- Name: stb_tab_vendor; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.stb_tab_vendor (
    vendor_id character varying(6) NOT NULL,
    vendor_name character varying(64) NOT NULL,
    vendor_add character varying(64) NOT NULL,
    remark character varying(100),
    staff_id character varying(30),
    telephone character varying(20),
    add_time numeric(10,0)
);


ALTER TABLE public.stb_tab_vendor OWNER TO gtmsmanager;

--
-- Name: stb_tab_vendor_oui; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.stb_tab_vendor_oui (
    vendor_id character varying(6) NOT NULL,
    oui character varying(6) NOT NULL
);


ALTER TABLE public.stb_tab_vendor_oui OWNER TO gtmsmanager;

--
-- Name: stb_task_batch_restart; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.stb_task_batch_restart (
    task_id character varying(50) NOT NULL,
    device_id character varying(50),
    dev_sn character varying(50),
    dev_type numeric(1,0) NOT NULL,
    add_time numeric(10,0) NOT NULL,
    operator character varying(50) NOT NULL,
    restart_status numeric(2,0) NOT NULL,
    restart_time numeric(10,0)
);


ALTER TABLE public.stb_task_batch_restart OWNER TO gtmsmanager;

--
-- Name: sys_announcement; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.sys_announcement (
    id character varying(32) NOT NULL,
    titile character varying(100),
    msg_content text,
    start_time timestamp without time zone,
    end_time timestamp without time zone,
    sender character varying(100),
    priority character varying(255),
    msg_category character varying(10) NOT NULL,
    msg_type character varying(10),
    send_status character varying(10),
    send_time timestamp without time zone,
    cancel_time timestamp without time zone,
    del_flag character varying(1),
    bus_type character varying(20),
    bus_id character varying(50),
    open_type character varying(20),
    open_page character varying(255),
    create_by character varying(32),
    create_time timestamp without time zone,
    update_by character varying(32),
    update_time timestamp without time zone,
    user_ids text,
    msg_abstract text,
    dt_task_id character varying(100)
);


ALTER TABLE public.sys_announcement OWNER TO gtmsmanager;

--
-- Name: TABLE sys_announcement; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON TABLE public.sys_announcement IS '系统通告表';


--
-- Name: COLUMN sys_announcement.titile; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_announcement.titile IS '标题';


--
-- Name: COLUMN sys_announcement.msg_content; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_announcement.msg_content IS '内容';


--
-- Name: COLUMN sys_announcement.start_time; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_announcement.start_time IS '开始时间';


--
-- Name: COLUMN sys_announcement.end_time; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_announcement.end_time IS '结束时间';


--
-- Name: COLUMN sys_announcement.sender; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_announcement.sender IS '发布人';


--
-- Name: COLUMN sys_announcement.priority; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_announcement.priority IS '优先级（L低，M中，H高）';


--
-- Name: COLUMN sys_announcement.msg_category; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_announcement.msg_category IS '消息类型1:通知公告2:系统消息';


--
-- Name: COLUMN sys_announcement.msg_type; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_announcement.msg_type IS '通告对象类型（USER:指定用户，ALL:全体用户）';


--
-- Name: COLUMN sys_announcement.send_status; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_announcement.send_status IS '发布状态（0未发布，1已发布，2已撤销）';


--
-- Name: COLUMN sys_announcement.send_time; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_announcement.send_time IS '发布时间';


--
-- Name: COLUMN sys_announcement.cancel_time; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_announcement.cancel_time IS '撤销时间';


--
-- Name: COLUMN sys_announcement.del_flag; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_announcement.del_flag IS '删除状态（0，正常，1已删除）';


--
-- Name: COLUMN sys_announcement.bus_type; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_announcement.bus_type IS '业务类型(email:邮件 bpm:流程)';


--
-- Name: COLUMN sys_announcement.bus_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_announcement.bus_id IS '业务id';


--
-- Name: COLUMN sys_announcement.open_type; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_announcement.open_type IS '打开方式(组件：component 路由：url)';


--
-- Name: COLUMN sys_announcement.open_page; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_announcement.open_page IS '组件/路由 地址';


--
-- Name: COLUMN sys_announcement.create_by; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_announcement.create_by IS '创建人';


--
-- Name: COLUMN sys_announcement.create_time; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_announcement.create_time IS '创建时间';


--
-- Name: COLUMN sys_announcement.update_by; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_announcement.update_by IS '更新人';


--
-- Name: COLUMN sys_announcement.update_time; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_announcement.update_time IS '更新时间';


--
-- Name: COLUMN sys_announcement.user_ids; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_announcement.user_ids IS '指定用户';


--
-- Name: COLUMN sys_announcement.msg_abstract; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_announcement.msg_abstract IS '摘要';


--
-- Name: COLUMN sys_announcement.dt_task_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_announcement.dt_task_id IS '钉钉task_id，用于撤回消息';


--
-- Name: sys_announcement_send; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.sys_announcement_send (
    id character varying(32),
    annt_id character varying(32),
    user_id character varying(32),
    read_flag character varying(10),
    read_time timestamp without time zone,
    create_by character varying(32),
    create_time timestamp without time zone,
    update_by character varying(32),
    update_time timestamp without time zone
);


ALTER TABLE public.sys_announcement_send OWNER TO gtmsmanager;

--
-- Name: TABLE sys_announcement_send; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON TABLE public.sys_announcement_send IS '用户通告阅读标记表';


--
-- Name: COLUMN sys_announcement_send.annt_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_announcement_send.annt_id IS '通告ID';


--
-- Name: COLUMN sys_announcement_send.user_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_announcement_send.user_id IS '用户id';


--
-- Name: COLUMN sys_announcement_send.read_flag; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_announcement_send.read_flag IS '阅读状态（0未读，1已读）';


--
-- Name: COLUMN sys_announcement_send.read_time; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_announcement_send.read_time IS '阅读时间';


--
-- Name: COLUMN sys_announcement_send.create_by; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_announcement_send.create_by IS '创建人';


--
-- Name: COLUMN sys_announcement_send.create_time; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_announcement_send.create_time IS '创建时间';


--
-- Name: COLUMN sys_announcement_send.update_by; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_announcement_send.update_by IS '更新人';


--
-- Name: COLUMN sys_announcement_send.update_time; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_announcement_send.update_time IS '更新时间';


--
-- Name: sys_category; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.sys_category (
    id character varying(36) NOT NULL,
    pid character varying(36),
    name character varying(100),
    code character varying(100),
    create_by character varying(50),
    create_time timestamp without time zone,
    update_by character varying(50),
    update_time timestamp without time zone,
    sys_org_code character varying(64),
    has_child character varying(3)
);


ALTER TABLE public.sys_category OWNER TO gtmsmanager;

--
-- Name: COLUMN sys_category.pid; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_category.pid IS '父级节点';


--
-- Name: COLUMN sys_category.name; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_category.name IS '类型名称';


--
-- Name: COLUMN sys_category.code; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_category.code IS '类型编码';


--
-- Name: COLUMN sys_category.create_by; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_category.create_by IS '创建人';


--
-- Name: COLUMN sys_category.create_time; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_category.create_time IS '创建日期';


--
-- Name: COLUMN sys_category.update_by; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_category.update_by IS '更新人';


--
-- Name: COLUMN sys_category.update_time; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_category.update_time IS '更新日期';


--
-- Name: COLUMN sys_category.sys_org_code; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_category.sys_org_code IS '所属部门';


--
-- Name: COLUMN sys_category.has_child; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_category.has_child IS '是否有子节点';


--
-- Name: sys_check_rule; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.sys_check_rule (
    id character varying(32) NOT NULL,
    rule_name character varying(100),
    rule_code character varying(100),
    rule_json text,
    rule_description character varying(200),
    update_by character varying(32),
    update_time timestamp without time zone,
    create_by character varying(32),
    create_time timestamp without time zone
);


ALTER TABLE public.sys_check_rule OWNER TO gtmsmanager;

--
-- Name: COLUMN sys_check_rule.id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_check_rule.id IS '主键id';


--
-- Name: COLUMN sys_check_rule.rule_name; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_check_rule.rule_name IS '规则名称';


--
-- Name: COLUMN sys_check_rule.rule_code; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_check_rule.rule_code IS '规则Code';


--
-- Name: COLUMN sys_check_rule.rule_json; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_check_rule.rule_json IS '规则JSON';


--
-- Name: COLUMN sys_check_rule.rule_description; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_check_rule.rule_description IS '规则描述';


--
-- Name: COLUMN sys_check_rule.update_by; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_check_rule.update_by IS '更新人';


--
-- Name: COLUMN sys_check_rule.update_time; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_check_rule.update_time IS '更新时间';


--
-- Name: COLUMN sys_check_rule.create_by; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_check_rule.create_by IS '创建人';


--
-- Name: COLUMN sys_check_rule.create_time; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_check_rule.create_time IS '创建时间';


--
-- Name: sys_data_source; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.sys_data_source (
    id character varying(36) NOT NULL,
    code character varying(100),
    name character varying(100),
    remark character varying(200),
    db_type character varying(10),
    db_driver character varying(100),
    db_url text,
    db_name character varying(100),
    db_username character varying(100),
    db_password character varying(100),
    create_by character varying(50),
    create_time timestamp without time zone,
    update_by character varying(50),
    update_time timestamp without time zone,
    sys_org_code character varying(64)
);


ALTER TABLE public.sys_data_source OWNER TO gtmsmanager;

--
-- Name: COLUMN sys_data_source.code; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_data_source.code IS '数据源编码';


--
-- Name: COLUMN sys_data_source.name; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_data_source.name IS '数据源名称';


--
-- Name: COLUMN sys_data_source.remark; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_data_source.remark IS '备注';


--
-- Name: COLUMN sys_data_source.db_type; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_data_source.db_type IS '数据库类型';


--
-- Name: COLUMN sys_data_source.db_driver; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_data_source.db_driver IS '驱动类';


--
-- Name: COLUMN sys_data_source.db_url; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_data_source.db_url IS '数据源地址';


--
-- Name: COLUMN sys_data_source.db_name; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_data_source.db_name IS '数据库名称';


--
-- Name: COLUMN sys_data_source.db_username; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_data_source.db_username IS '用户名';


--
-- Name: COLUMN sys_data_source.db_password; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_data_source.db_password IS '密码';


--
-- Name: COLUMN sys_data_source.create_by; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_data_source.create_by IS '创建人';


--
-- Name: COLUMN sys_data_source.create_time; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_data_source.create_time IS '创建日期';


--
-- Name: COLUMN sys_data_source.update_by; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_data_source.update_by IS '更新人';


--
-- Name: COLUMN sys_data_source.update_time; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_data_source.update_time IS '更新日期';


--
-- Name: COLUMN sys_data_source.sys_org_code; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_data_source.sys_org_code IS '所属部门';


--
-- Name: sys_depart; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.sys_depart (
    id character varying(32) NOT NULL,
    parent_id character varying(32),
    depart_name character varying(100) NOT NULL,
    depart_name_en text,
    depart_name_abbr text,
    depart_order numeric(11,0),
    description text,
    org_category character varying(10) NOT NULL,
    org_type character varying(10),
    org_code character varying(64) NOT NULL,
    mobile character varying(32),
    fax character varying(32),
    address character varying(100),
    memo text,
    status character varying(1),
    del_flag character varying(1),
    qywx_identifier character varying(100),
    create_by character varying(32),
    create_time timestamp without time zone,
    update_by character varying(32),
    update_time timestamp without time zone
);


ALTER TABLE public.sys_depart OWNER TO gtmsmanager;

--
-- Name: TABLE sys_depart; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON TABLE public.sys_depart IS '组织机构表';


--
-- Name: COLUMN sys_depart.id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_depart.id IS 'ID';


--
-- Name: COLUMN sys_depart.parent_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_depart.parent_id IS '父机构ID';


--
-- Name: COLUMN sys_depart.depart_name; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_depart.depart_name IS '机构/部门名称';


--
-- Name: COLUMN sys_depart.depart_name_en; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_depart.depart_name_en IS '英文名';


--
-- Name: COLUMN sys_depart.depart_name_abbr; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_depart.depart_name_abbr IS '缩写';


--
-- Name: COLUMN sys_depart.depart_order; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_depart.depart_order IS '排序';


--
-- Name: COLUMN sys_depart.description; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_depart.description IS '描述';


--
-- Name: COLUMN sys_depart.org_category; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_depart.org_category IS '机构类别 1公司，2组织机构，2岗位';


--
-- Name: COLUMN sys_depart.org_type; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_depart.org_type IS '机构类型 1一级部门 2子部门';


--
-- Name: COLUMN sys_depart.org_code; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_depart.org_code IS '机构编码';


--
-- Name: COLUMN sys_depart.mobile; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_depart.mobile IS '手机号';


--
-- Name: COLUMN sys_depart.fax; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_depart.fax IS '传真';


--
-- Name: COLUMN sys_depart.address; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_depart.address IS '地址';


--
-- Name: COLUMN sys_depart.memo; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_depart.memo IS '备注';


--
-- Name: COLUMN sys_depart.status; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_depart.status IS '状态（1启用，0不启用）';


--
-- Name: COLUMN sys_depart.del_flag; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_depart.del_flag IS '删除状态（0，正常，1已删除）';


--
-- Name: COLUMN sys_depart.qywx_identifier; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_depart.qywx_identifier IS '对接企业微信的ID';


--
-- Name: COLUMN sys_depart.create_by; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_depart.create_by IS '创建人';


--
-- Name: COLUMN sys_depart.create_time; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_depart.create_time IS '创建日期';


--
-- Name: COLUMN sys_depart.update_by; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_depart.update_by IS '更新人';


--
-- Name: COLUMN sys_depart.update_time; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_depart.update_time IS '更新日期';


--
-- Name: sys_depart_permission; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.sys_depart_permission (
    id character varying(32) NOT NULL,
    depart_id character varying(32),
    permission_id character varying(32),
    data_rule_ids text
);


ALTER TABLE public.sys_depart_permission OWNER TO gtmsmanager;

--
-- Name: TABLE sys_depart_permission; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON TABLE public.sys_depart_permission IS '部门权限表';


--
-- Name: COLUMN sys_depart_permission.depart_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_depart_permission.depart_id IS '部门id';


--
-- Name: COLUMN sys_depart_permission.permission_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_depart_permission.permission_id IS '权限id';


--
-- Name: COLUMN sys_depart_permission.data_rule_ids; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_depart_permission.data_rule_ids IS '数据规则id';


--
-- Name: sys_depart_role; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.sys_depart_role (
    id character varying(32) NOT NULL,
    depart_id character varying(32),
    role_name character varying(200),
    role_code character varying(100),
    description character varying(255),
    create_by character varying(32),
    create_time timestamp without time zone,
    update_by character varying(32),
    update_time timestamp without time zone
);


ALTER TABLE public.sys_depart_role OWNER TO gtmsmanager;

--
-- Name: TABLE sys_depart_role; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON TABLE public.sys_depart_role IS '部门角色表';


--
-- Name: COLUMN sys_depart_role.depart_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_depart_role.depart_id IS '部门id';


--
-- Name: COLUMN sys_depart_role.role_name; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_depart_role.role_name IS '部门角色名称';


--
-- Name: COLUMN sys_depart_role.role_code; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_depart_role.role_code IS '部门角色编码';


--
-- Name: COLUMN sys_depart_role.description; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_depart_role.description IS '描述';


--
-- Name: COLUMN sys_depart_role.create_by; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_depart_role.create_by IS '创建人';


--
-- Name: COLUMN sys_depart_role.create_time; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_depart_role.create_time IS '创建时间';


--
-- Name: COLUMN sys_depart_role.update_by; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_depart_role.update_by IS '更新人';


--
-- Name: COLUMN sys_depart_role.update_time; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_depart_role.update_time IS '更新时间';


--
-- Name: sys_depart_role_permission; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.sys_depart_role_permission (
    id character varying(32) NOT NULL,
    depart_id character varying(32),
    role_id character varying(32),
    permission_id character varying(32),
    data_rule_ids text,
    operate_date timestamp without time zone,
    operate_ip character varying(20)
);


ALTER TABLE public.sys_depart_role_permission OWNER TO gtmsmanager;

--
-- Name: TABLE sys_depart_role_permission; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON TABLE public.sys_depart_role_permission IS '部门角色权限表';


--
-- Name: COLUMN sys_depart_role_permission.depart_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_depart_role_permission.depart_id IS '部门id';


--
-- Name: COLUMN sys_depart_role_permission.role_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_depart_role_permission.role_id IS '角色id';


--
-- Name: COLUMN sys_depart_role_permission.permission_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_depart_role_permission.permission_id IS '权限id';


--
-- Name: COLUMN sys_depart_role_permission.data_rule_ids; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_depart_role_permission.data_rule_ids IS '数据权限ids';


--
-- Name: COLUMN sys_depart_role_permission.operate_date; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_depart_role_permission.operate_date IS '操作时间';


--
-- Name: COLUMN sys_depart_role_permission.operate_ip; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_depart_role_permission.operate_ip IS '操作ip';


--
-- Name: sys_depart_role_user; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.sys_depart_role_user (
    id character varying(32) NOT NULL,
    user_id character varying(32),
    drole_id character varying(32)
);


ALTER TABLE public.sys_depart_role_user OWNER TO gtmsmanager;

--
-- Name: TABLE sys_depart_role_user; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON TABLE public.sys_depart_role_user IS '部门角色用户表';


--
-- Name: COLUMN sys_depart_role_user.id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_depart_role_user.id IS '主键id';


--
-- Name: COLUMN sys_depart_role_user.user_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_depart_role_user.user_id IS '用户id';


--
-- Name: COLUMN sys_depart_role_user.drole_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_depart_role_user.drole_id IS '角色id';


--
-- Name: sys_dict; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.sys_dict (
    id character varying(32) NOT NULL,
    dict_name character varying(100) NOT NULL,
    dict_name_en character varying(255),
    dict_name_es character varying(255),
    dict_code character varying(100) NOT NULL,
    description character varying(255),
    del_flag numeric(11,0),
    create_by character varying(32),
    create_time timestamp without time zone,
    update_by character varying(32),
    update_time timestamp without time zone,
    type numeric(11,0)
);


ALTER TABLE public.sys_dict OWNER TO gtmsmanager;

--
-- Name: COLUMN sys_dict.dict_name; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_dict.dict_name IS '字典名称';


--
-- Name: COLUMN sys_dict.dict_name_en; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_dict.dict_name_en IS '字典项文本(英)';


--
-- Name: COLUMN sys_dict.dict_name_es; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_dict.dict_name_es IS '字典文本(西班牙)';


--
-- Name: COLUMN sys_dict.dict_code; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_dict.dict_code IS '字典编码';


--
-- Name: COLUMN sys_dict.description; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_dict.description IS '描述';


--
-- Name: COLUMN sys_dict.del_flag; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_dict.del_flag IS '删除状态';


--
-- Name: COLUMN sys_dict.create_by; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_dict.create_by IS '创建人';


--
-- Name: COLUMN sys_dict.create_time; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_dict.create_time IS '创建时间';


--
-- Name: COLUMN sys_dict.update_by; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_dict.update_by IS '更新人';


--
-- Name: COLUMN sys_dict.update_time; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_dict.update_time IS '更新时间';


--
-- Name: COLUMN sys_dict.type; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_dict.type IS '字典类型0为string,1为number';


--
-- Name: sys_dict_item; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.sys_dict_item (
    id character varying(32) NOT NULL,
    dict_id character varying(32),
    item_text character varying(100) NOT NULL,
    item_value character varying(100) NOT NULL,
    description character varying(255),
    sort_order numeric(11,0),
    status numeric(11,0),
    create_by character varying(32),
    create_time timestamp without time zone,
    update_by character varying(32),
    update_time timestamp without time zone,
    item_text_en character varying(100),
    item_text_es character varying(255)
);


ALTER TABLE public.sys_dict_item OWNER TO gtmsmanager;

--
-- Name: COLUMN sys_dict_item.dict_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_dict_item.dict_id IS '字典id';


--
-- Name: COLUMN sys_dict_item.item_text; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_dict_item.item_text IS '字典项文本';


--
-- Name: COLUMN sys_dict_item.item_value; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_dict_item.item_value IS '字典项值';


--
-- Name: COLUMN sys_dict_item.description; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_dict_item.description IS '描述';


--
-- Name: COLUMN sys_dict_item.sort_order; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_dict_item.sort_order IS '排序';


--
-- Name: COLUMN sys_dict_item.status; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_dict_item.status IS '状态（1启用 0不启用）';


--
-- Name: COLUMN sys_dict_item.item_text_en; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_dict_item.item_text_en IS '字典项文本(英)';


--
-- Name: COLUMN sys_dict_item.item_text_es; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_dict_item.item_text_es IS '字典文本(西班牙)';


--
-- Name: sys_fill_rule; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.sys_fill_rule (
    id character varying(32) NOT NULL,
    rule_name character varying(100),
    rule_code character varying(100),
    rule_class character varying(100),
    rule_params character varying(200),
    update_by character varying(32),
    update_time timestamp without time zone,
    create_by character varying(32),
    create_time timestamp without time zone
);


ALTER TABLE public.sys_fill_rule OWNER TO gtmsmanager;

--
-- Name: COLUMN sys_fill_rule.id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_fill_rule.id IS '主键ID';


--
-- Name: COLUMN sys_fill_rule.rule_name; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_fill_rule.rule_name IS '规则名称';


--
-- Name: COLUMN sys_fill_rule.rule_code; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_fill_rule.rule_code IS '规则Code';


--
-- Name: COLUMN sys_fill_rule.rule_class; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_fill_rule.rule_class IS '规则实现类';


--
-- Name: COLUMN sys_fill_rule.rule_params; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_fill_rule.rule_params IS '规则参数';


--
-- Name: COLUMN sys_fill_rule.update_by; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_fill_rule.update_by IS '修改人';


--
-- Name: COLUMN sys_fill_rule.update_time; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_fill_rule.update_time IS '修改时间';


--
-- Name: COLUMN sys_fill_rule.create_by; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_fill_rule.create_by IS '创建人';


--
-- Name: COLUMN sys_fill_rule.create_time; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_fill_rule.create_time IS '创建时间';


--
-- Name: sys_gateway_route; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.sys_gateway_route (
    id character varying(36) NOT NULL,
    router_id character varying(50),
    name character varying(32),
    uri character varying(32),
    predicates text,
    filters text,
    retryable numeric(11,0),
    strip_prefix numeric(11,0),
    persistable numeric(11,0),
    show_api numeric(11,0),
    status numeric(11,0),
    create_by character varying(50),
    create_time timestamp without time zone,
    update_by character varying(50),
    update_time timestamp without time zone,
    sys_org_code character varying(64)
);


ALTER TABLE public.sys_gateway_route OWNER TO gtmsmanager;

--
-- Name: COLUMN sys_gateway_route.router_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_gateway_route.router_id IS '路由ID';


--
-- Name: COLUMN sys_gateway_route.name; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_gateway_route.name IS '服务名';


--
-- Name: COLUMN sys_gateway_route.uri; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_gateway_route.uri IS '服务地址';


--
-- Name: COLUMN sys_gateway_route.predicates; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_gateway_route.predicates IS '断言';


--
-- Name: COLUMN sys_gateway_route.filters; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_gateway_route.filters IS '过滤器';


--
-- Name: COLUMN sys_gateway_route.retryable; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_gateway_route.retryable IS '是否重试:0-否 1-是';


--
-- Name: COLUMN sys_gateway_route.strip_prefix; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_gateway_route.strip_prefix IS '是否忽略前缀0-否 1-是';


--
-- Name: COLUMN sys_gateway_route.persistable; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_gateway_route.persistable IS '是否为保留数据:0-否 1-是';


--
-- Name: COLUMN sys_gateway_route.show_api; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_gateway_route.show_api IS '是否在接口文档中展示:0-否 1-是';


--
-- Name: COLUMN sys_gateway_route.status; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_gateway_route.status IS '状态:0-无效 1-有效';


--
-- Name: COLUMN sys_gateway_route.create_by; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_gateway_route.create_by IS '创建人';


--
-- Name: COLUMN sys_gateway_route.create_time; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_gateway_route.create_time IS '创建日期';


--
-- Name: COLUMN sys_gateway_route.update_by; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_gateway_route.update_by IS '更新人';


--
-- Name: COLUMN sys_gateway_route.update_time; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_gateway_route.update_time IS '更新日期';


--
-- Name: COLUMN sys_gateway_route.sys_org_code; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_gateway_route.sys_org_code IS '所属部门';


--
-- Name: sys_language_config; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.sys_language_config (
    id character varying(32) NOT NULL,
    language_code character varying(10) NOT NULL,
    language_name character varying(50) NOT NULL,
    field_suffix character varying(20),
    is_default smallint DEFAULT 0,
    status smallint DEFAULT 1,
    sort_no integer DEFAULT 0,
    create_time timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    update_time timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    country character varying(100)
);


ALTER TABLE public.sys_language_config OWNER TO gtmsmanager;

--
-- Name: COLUMN sys_language_config.language_code; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_language_config.language_code IS '语言代码，如：zh, en, es';


--
-- Name: COLUMN sys_language_config.language_name; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_language_config.language_name IS '语言名称，如：中文, English, Español';


--
-- Name: COLUMN sys_language_config.field_suffix; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_language_config.field_suffix IS '字段后缀，如：空字符串, En, Es';


--
-- Name: COLUMN sys_language_config.is_default; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_language_config.is_default IS '是否默认语言';


--
-- Name: COLUMN sys_language_config.status; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_language_config.status IS '状态：1启用，0禁用';


--
-- Name: COLUMN sys_language_config.sort_no; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_language_config.sort_no IS '排序号';


--
-- Name: COLUMN sys_language_config.country; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_language_config.country IS '地区';


--
-- Name: sys_log; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.sys_log (
    id character varying(32) NOT NULL,
    log_type numeric(11,0),
    log_content text,
    operate_type numeric(11,0),
    userid character varying(32),
    username character varying(100),
    ip character varying(100),
    method text,
    request_url character varying(255),
    request_param text,
    request_type character varying(10),
    cost_time numeric(20,0),
    create_by character varying(32),
    create_time timestamp without time zone,
    update_by character varying(32),
    update_time timestamp without time zone
);


ALTER TABLE public.sys_log OWNER TO gtmsmanager;

--
-- Name: TABLE sys_log; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON TABLE public.sys_log IS '系统日志表';


--
-- Name: COLUMN sys_log.log_type; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_log.log_type IS '日志类型（1登录日志，2操作日志）';


--
-- Name: COLUMN sys_log.log_content; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_log.log_content IS '日志内容';


--
-- Name: COLUMN sys_log.operate_type; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_log.operate_type IS '操作类型';


--
-- Name: COLUMN sys_log.userid; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_log.userid IS '操作用户账号';


--
-- Name: COLUMN sys_log.username; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_log.username IS '操作用户名称';


--
-- Name: COLUMN sys_log.ip; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_log.ip IS 'IP';


--
-- Name: COLUMN sys_log.method; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_log.method IS '请求java方法';


--
-- Name: COLUMN sys_log.request_url; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_log.request_url IS '请求路径';


--
-- Name: COLUMN sys_log.request_param; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_log.request_param IS '请求参数';


--
-- Name: COLUMN sys_log.request_type; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_log.request_type IS '请求类型';


--
-- Name: COLUMN sys_log.cost_time; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_log.cost_time IS '耗时';


--
-- Name: COLUMN sys_log.create_by; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_log.create_by IS '创建人';


--
-- Name: COLUMN sys_log.create_time; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_log.create_time IS '创建时间';


--
-- Name: COLUMN sys_log.update_by; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_log.update_by IS '更新人';


--
-- Name: COLUMN sys_log.update_time; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_log.update_time IS '更新时间';


--
-- Name: sys_permission; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.sys_permission (
    id character varying(32),
    parent_id character varying(32),
    name character varying(100),
    url character varying(255),
    component character varying(255),
    component_name character varying(100),
    redirect character varying(255),
    menu_type numeric(11,0),
    perms character varying(255),
    perms_type character varying(10),
    sort_no numeric(8,2),
    always_show numeric(4,0),
    icon character varying(100),
    is_route numeric(4,0),
    is_leaf numeric(4,0),
    keep_alive numeric(4,0),
    hidden numeric(11,0),
    hide_tab numeric(11,0),
    description character varying(255),
    create_by character varying(32),
    create_time timestamp without time zone,
    update_by character varying(32),
    update_time timestamp without time zone,
    del_flag numeric(11,0),
    rule_flag numeric(11,0),
    status character varying(2),
    internal_or_external numeric(4,0),
    name_en character varying(100),
    name_es character varying(100)
);

ALTER TABLE ONLY public.sys_permission REPLICA IDENTITY FULL;


ALTER TABLE public.sys_permission OWNER TO gtmsmanager;

--
-- Name: sys_permission_backup; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.sys_permission_backup (
    id character varying(32),
    parent_id character varying(32),
    name character varying(100),
    url character varying(255),
    component character varying(255),
    component_name character varying(100),
    redirect character varying(255),
    menu_type numeric(11,0),
    perms character varying(255),
    perms_type character varying(10),
    sort_no numeric(8,2),
    always_show numeric(4,0),
    icon character varying(100),
    is_route numeric(4,0),
    is_leaf numeric(4,0),
    keep_alive numeric(4,0),
    hidden numeric(11,0),
    hide_tab numeric(11,0),
    description character varying(255),
    create_by character varying(32),
    create_time timestamp without time zone,
    update_by character varying(32),
    update_time timestamp without time zone,
    del_flag numeric(11,0),
    rule_flag numeric(11,0),
    status character varying(2),
    internal_or_external numeric(4,0),
    name_en character varying(100),
    name_es character varying(100)
);


ALTER TABLE public.sys_permission_backup OWNER TO gtmsmanager;

--
-- Name: sys_permission_bak0925; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.sys_permission_bak0925 (
    id character varying(32) NOT NULL,
    parent_id character varying(32),
    name character varying(100),
    url character varying(255),
    component character varying(255),
    component_name character varying(100),
    redirect character varying(255),
    menu_type numeric(11,0),
    perms character varying(255),
    perms_type character varying(10),
    sort_no numeric(8,2),
    always_show numeric(4,0),
    icon character varying(100),
    is_route numeric(4,0),
    is_leaf numeric(4,0),
    keep_alive numeric(4,0),
    hidden numeric(11,0),
    hide_tab numeric(11,0),
    description character varying(255),
    create_by character varying(32),
    create_time timestamp without time zone,
    update_by character varying(32),
    update_time timestamp without time zone,
    del_flag numeric(11,0),
    rule_flag numeric(11,0),
    status character varying(2),
    internal_or_external numeric(4,0),
    name_en character varying(100)
);


ALTER TABLE public.sys_permission_bak0925 OWNER TO gtmsmanager;

--
-- Name: COLUMN sys_permission_bak0925.id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_permission_bak0925.id IS '主键id';


--
-- Name: COLUMN sys_permission_bak0925.parent_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_permission_bak0925.parent_id IS '父id';


--
-- Name: COLUMN sys_permission_bak0925.name; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_permission_bak0925.name IS '菜单标题';


--
-- Name: COLUMN sys_permission_bak0925.url; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_permission_bak0925.url IS '路径';


--
-- Name: COLUMN sys_permission_bak0925.component; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_permission_bak0925.component IS '组件';


--
-- Name: COLUMN sys_permission_bak0925.component_name; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_permission_bak0925.component_name IS '组件名字';


--
-- Name: COLUMN sys_permission_bak0925.redirect; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_permission_bak0925.redirect IS '一级菜单跳转地址';


--
-- Name: COLUMN sys_permission_bak0925.menu_type; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_permission_bak0925.menu_type IS '菜单类型(0:一级菜单; 1:子菜单:2:按钮权限)';


--
-- Name: COLUMN sys_permission_bak0925.perms; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_permission_bak0925.perms IS '菜单权限编码';


--
-- Name: COLUMN sys_permission_bak0925.perms_type; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_permission_bak0925.perms_type IS '权限策略1显示2禁用';


--
-- Name: COLUMN sys_permission_bak0925.sort_no; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_permission_bak0925.sort_no IS '菜单排序';


--
-- Name: COLUMN sys_permission_bak0925.always_show; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_permission_bak0925.always_show IS '聚合子路由: 1是0否';


--
-- Name: COLUMN sys_permission_bak0925.icon; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_permission_bak0925.icon IS '菜单图标';


--
-- Name: COLUMN sys_permission_bak0925.is_route; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_permission_bak0925.is_route IS '是否路由菜单: 0:不是  1:是（默认值1）';


--
-- Name: COLUMN sys_permission_bak0925.is_leaf; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_permission_bak0925.is_leaf IS '是否叶子节点:    1:是   0:不是';


--
-- Name: COLUMN sys_permission_bak0925.keep_alive; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_permission_bak0925.keep_alive IS '是否缓存该页面:    1:是   0:不是';


--
-- Name: COLUMN sys_permission_bak0925.hidden; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_permission_bak0925.hidden IS '是否隐藏路由: 0否,1是';


--
-- Name: COLUMN sys_permission_bak0925.hide_tab; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_permission_bak0925.hide_tab IS '是否隐藏tab: 0否,1是';


--
-- Name: COLUMN sys_permission_bak0925.description; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_permission_bak0925.description IS '描述';


--
-- Name: COLUMN sys_permission_bak0925.create_by; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_permission_bak0925.create_by IS '创建人';


--
-- Name: COLUMN sys_permission_bak0925.create_time; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_permission_bak0925.create_time IS '创建时间';


--
-- Name: COLUMN sys_permission_bak0925.update_by; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_permission_bak0925.update_by IS '更新人';


--
-- Name: COLUMN sys_permission_bak0925.update_time; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_permission_bak0925.update_time IS '更新时间';


--
-- Name: COLUMN sys_permission_bak0925.del_flag; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_permission_bak0925.del_flag IS '删除状态 0正常 1已删除';


--
-- Name: COLUMN sys_permission_bak0925.rule_flag; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_permission_bak0925.rule_flag IS '是否添加数据权限1是0否';


--
-- Name: COLUMN sys_permission_bak0925.status; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_permission_bak0925.status IS '按钮权限状态(0无效1有效)';


--
-- Name: COLUMN sys_permission_bak0925.internal_or_external; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_permission_bak0925.internal_or_external IS '外链菜单打开方式 0/内部打开 1/外部打开';


--
-- Name: COLUMN sys_permission_bak0925.name_en; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_permission_bak0925.name_en IS '菜单标题(英)';


--
-- Name: sys_permission_data_rule; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.sys_permission_data_rule (
    id integer NOT NULL,
    permission_id character varying(32),
    rule_name character varying(32),
    rule_column character varying(32),
    rule_conditions character varying(64),
    rule_value character varying(255),
    status smallint,
    create_time timestamp without time zone,
    create_by character varying(64),
    update_time timestamp without time zone,
    update_by timestamp without time zone
);


ALTER TABLE public.sys_permission_data_rule OWNER TO gtmsmanager;

--
-- Name: COLUMN sys_permission_data_rule.status; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_permission_data_rule.status IS '状态值 1有效 0无效';


--
-- Name: sys_permission_tab_data_id_seq; Type: SEQUENCE; Schema: public; Owner: gtmsmanager
--

CREATE SEQUENCE public.sys_permission_tab_data_id_seq
    START WITH 10000000
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 10;


ALTER SEQUENCE public.sys_permission_tab_data_id_seq OWNER TO gtmsmanager;

--
-- Name: sys_permission_tapdata_id_seq; Type: SEQUENCE; Schema: public; Owner: gtmsmanager
--

CREATE SEQUENCE public.sys_permission_tapdata_id_seq
    START WITH 10000000
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 10;


ALTER SEQUENCE public.sys_permission_tapdata_id_seq OWNER TO gtmsmanager;

--
-- Name: sys_position; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.sys_position (
    id character varying(32) NOT NULL,
    code character varying(100),
    name character varying(100),
    post_rank character varying(2),
    company_id character varying(255),
    create_by character varying(50),
    create_time timestamp without time zone,
    update_by character varying(50),
    update_time timestamp without time zone,
    sys_org_code character varying(50)
);


ALTER TABLE public.sys_position OWNER TO gtmsmanager;

--
-- Name: COLUMN sys_position.code; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_position.code IS '职务编码';


--
-- Name: COLUMN sys_position.name; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_position.name IS '职务名称';


--
-- Name: COLUMN sys_position.post_rank; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_position.post_rank IS '职级';


--
-- Name: COLUMN sys_position.company_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_position.company_id IS '公司id';


--
-- Name: COLUMN sys_position.create_by; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_position.create_by IS '创建人';


--
-- Name: COLUMN sys_position.create_time; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_position.create_time IS '创建时间';


--
-- Name: COLUMN sys_position.update_by; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_position.update_by IS '修改人';


--
-- Name: COLUMN sys_position.update_time; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_position.update_time IS '修改时间';


--
-- Name: COLUMN sys_position.sys_org_code; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_position.sys_org_code IS '组织机构编码';


--
-- Name: sys_quartz_job; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.sys_quartz_job (
    id character varying(32) NOT NULL,
    create_by character varying(32),
    create_time timestamp without time zone,
    del_flag numeric(11,0),
    update_by character varying(32),
    update_time timestamp without time zone,
    job_class_name character varying(255),
    cron_expression character varying(255),
    parameter character varying(255),
    description character varying(255),
    status numeric(11,0)
);


ALTER TABLE public.sys_quartz_job OWNER TO gtmsmanager;

--
-- Name: COLUMN sys_quartz_job.create_by; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_quartz_job.create_by IS '创建人';


--
-- Name: COLUMN sys_quartz_job.create_time; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_quartz_job.create_time IS '创建时间';


--
-- Name: COLUMN sys_quartz_job.del_flag; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_quartz_job.del_flag IS '删除状态';


--
-- Name: COLUMN sys_quartz_job.update_by; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_quartz_job.update_by IS '修改人';


--
-- Name: COLUMN sys_quartz_job.update_time; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_quartz_job.update_time IS '修改时间';


--
-- Name: COLUMN sys_quartz_job.job_class_name; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_quartz_job.job_class_name IS '任务类名';


--
-- Name: COLUMN sys_quartz_job.cron_expression; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_quartz_job.cron_expression IS 'cron表达式';


--
-- Name: COLUMN sys_quartz_job.parameter; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_quartz_job.parameter IS '参数';


--
-- Name: COLUMN sys_quartz_job.description; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_quartz_job.description IS '描述';


--
-- Name: COLUMN sys_quartz_job.status; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_quartz_job.status IS '状态 0正常 -1停止';


--
-- Name: sys_role; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.sys_role (
    id character varying(32) NOT NULL,
    role_name character varying(200),
    role_code character varying(100) NOT NULL,
    description character varying(255),
    create_by character varying(32),
    create_time timestamp without time zone,
    update_by character varying(32),
    update_time timestamp without time zone
);


ALTER TABLE public.sys_role OWNER TO gtmsmanager;

--
-- Name: TABLE sys_role; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON TABLE public.sys_role IS '角色表';


--
-- Name: COLUMN sys_role.id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_role.id IS '主键id';


--
-- Name: COLUMN sys_role.role_name; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_role.role_name IS '角色名称';


--
-- Name: COLUMN sys_role.role_code; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_role.role_code IS '角色编码';


--
-- Name: COLUMN sys_role.description; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_role.description IS '描述';


--
-- Name: COLUMN sys_role.create_by; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_role.create_by IS '创建人';


--
-- Name: COLUMN sys_role.create_time; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_role.create_time IS '创建时间';


--
-- Name: COLUMN sys_role.update_by; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_role.update_by IS '更新人';


--
-- Name: COLUMN sys_role.update_time; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_role.update_time IS '更新时间';


--
-- Name: sys_role_permission; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.sys_role_permission (
    id character varying(32) NOT NULL,
    role_id character varying(32),
    permission_id character varying(32),
    data_rule_ids text,
    operate_date timestamp without time zone,
    operate_ip character varying(100)
);


ALTER TABLE public.sys_role_permission OWNER TO gtmsmanager;

--
-- Name: TABLE sys_role_permission; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON TABLE public.sys_role_permission IS '角色权限表';


--
-- Name: COLUMN sys_role_permission.role_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_role_permission.role_id IS '角色id';


--
-- Name: COLUMN sys_role_permission.permission_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_role_permission.permission_id IS '权限id';


--
-- Name: COLUMN sys_role_permission.data_rule_ids; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_role_permission.data_rule_ids IS '数据权限ids';


--
-- Name: COLUMN sys_role_permission.operate_date; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_role_permission.operate_date IS '操作时间';


--
-- Name: COLUMN sys_role_permission.operate_ip; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_role_permission.operate_ip IS '操作ip';


--
-- Name: sys_sms_template; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.sys_sms_template (
    id character varying(32) NOT NULL,
    template_name character varying(50),
    template_code character varying(32) NOT NULL,
    template_type character varying(1) NOT NULL,
    template_content text NOT NULL,
    template_test_json text,
    create_time timestamp without time zone,
    create_by character varying(32),
    update_time timestamp without time zone,
    update_by character varying(32)
);


ALTER TABLE public.sys_sms_template OWNER TO gtmsmanager;

--
-- Name: COLUMN sys_sms_template.id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_sms_template.id IS '主键';


--
-- Name: COLUMN sys_sms_template.template_name; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_sms_template.template_name IS '模板标题';


--
-- Name: COLUMN sys_sms_template.template_code; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_sms_template.template_code IS '模板CODE';


--
-- Name: COLUMN sys_sms_template.template_type; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_sms_template.template_type IS '模板类型：1短信 2邮件 3微信';


--
-- Name: COLUMN sys_sms_template.template_content; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_sms_template.template_content IS '模板内容';


--
-- Name: COLUMN sys_sms_template.template_test_json; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_sms_template.template_test_json IS '模板测试json';


--
-- Name: COLUMN sys_sms_template.create_time; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_sms_template.create_time IS '创建日期';


--
-- Name: COLUMN sys_sms_template.create_by; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_sms_template.create_by IS '创建人登录名称';


--
-- Name: COLUMN sys_sms_template.update_time; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_sms_template.update_time IS '更新日期';


--
-- Name: COLUMN sys_sms_template.update_by; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_sms_template.update_by IS '更新人登录名称';


--
-- Name: sys_tenant; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.sys_tenant (
    id numeric(11,0) NOT NULL,
    name character varying(100),
    create_time timestamp without time zone,
    create_by character varying(100),
    begin_date timestamp without time zone,
    end_date timestamp without time zone,
    status numeric(11,0)
);


ALTER TABLE public.sys_tenant OWNER TO gtmsmanager;

--
-- Name: TABLE sys_tenant; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON TABLE public.sys_tenant IS '多租户信息表';


--
-- Name: COLUMN sys_tenant.id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_tenant.id IS '租户编码';


--
-- Name: COLUMN sys_tenant.name; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_tenant.name IS '租户名称';


--
-- Name: COLUMN sys_tenant.create_time; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_tenant.create_time IS '创建时间';


--
-- Name: COLUMN sys_tenant.create_by; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_tenant.create_by IS '创建人';


--
-- Name: COLUMN sys_tenant.begin_date; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_tenant.begin_date IS '开始时间';


--
-- Name: COLUMN sys_tenant.end_date; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_tenant.end_date IS '结束时间';


--
-- Name: COLUMN sys_tenant.status; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_tenant.status IS '状态 1正常 0冻结';


--
-- Name: sys_user; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.sys_user (
    id character varying(32) NOT NULL,
    username character varying(100),
    realname character varying(100),
    password character varying(255),
    salt character varying(45),
    avatar character varying(255),
    birthday timestamp without time zone,
    sex numeric(4,0),
    email character varying(45),
    phone character varying(45),
    org_code character varying(64),
    status numeric(4,0),
    del_flag numeric(4,0),
    third_id character varying(100),
    third_type character varying(100),
    activiti_sync numeric(4,0),
    work_no character varying(100),
    post character varying(100),
    telephone character varying(45),
    create_by character varying(32),
    create_time timestamp without time zone,
    update_by character varying(32),
    update_time timestamp without time zone,
    user_identity numeric(4,0),
    depart_ids text,
    rel_tenant_ids character varying(100),
    client_id character varying(64),
    city_id character varying(64),
    reset_flag numeric(4,0) DEFAULT 0
);


ALTER TABLE public.sys_user OWNER TO gtmsmanager;

--
-- Name: TABLE sys_user; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON TABLE public.sys_user IS '用户表';


--
-- Name: COLUMN sys_user.id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_user.id IS '主键id';


--
-- Name: COLUMN sys_user.username; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_user.username IS '登录账号';


--
-- Name: COLUMN sys_user.realname; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_user.realname IS '真实姓名';


--
-- Name: COLUMN sys_user.password; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_user.password IS '密码';


--
-- Name: COLUMN sys_user.salt; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_user.salt IS 'md5密码盐';


--
-- Name: COLUMN sys_user.avatar; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_user.avatar IS '头像';


--
-- Name: COLUMN sys_user.birthday; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_user.birthday IS '生日';


--
-- Name: COLUMN sys_user.sex; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_user.sex IS '性别(0-默认未知,1-男,2-女)';


--
-- Name: COLUMN sys_user.email; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_user.email IS '电子邮件';


--
-- Name: COLUMN sys_user.phone; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_user.phone IS '电话';


--
-- Name: COLUMN sys_user.org_code; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_user.org_code IS '机构编码';


--
-- Name: COLUMN sys_user.status; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_user.status IS '性别(1-正常,2-冻结)';


--
-- Name: COLUMN sys_user.del_flag; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_user.del_flag IS '删除状态(0-正常,1-已删除)';


--
-- Name: COLUMN sys_user.third_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_user.third_id IS '第三方登录的唯一标识';


--
-- Name: COLUMN sys_user.third_type; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_user.third_type IS '第三方类型';


--
-- Name: COLUMN sys_user.activiti_sync; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_user.activiti_sync IS '同步工作流引擎(1-同步,0-不同步)';


--
-- Name: COLUMN sys_user.work_no; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_user.work_no IS '工号，唯一键';


--
-- Name: COLUMN sys_user.post; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_user.post IS '职务，关联职务表';


--
-- Name: COLUMN sys_user.telephone; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_user.telephone IS '座机号';


--
-- Name: COLUMN sys_user.create_by; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_user.create_by IS '创建人';


--
-- Name: COLUMN sys_user.create_time; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_user.create_time IS '创建时间';


--
-- Name: COLUMN sys_user.update_by; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_user.update_by IS '更新人';


--
-- Name: COLUMN sys_user.update_time; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_user.update_time IS '更新时间';


--
-- Name: COLUMN sys_user.user_identity; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_user.user_identity IS '身份（1普通成员 2上级）';


--
-- Name: COLUMN sys_user.depart_ids; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_user.depart_ids IS '负责部门';


--
-- Name: COLUMN sys_user.rel_tenant_ids; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_user.rel_tenant_ids IS '多租户标识';


--
-- Name: COLUMN sys_user.client_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_user.client_id IS '设备ID';


--
-- Name: sys_user_depart; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.sys_user_depart (
    id character varying(32) NOT NULL,
    user_id character varying(32),
    dep_id character varying(32)
);


ALTER TABLE public.sys_user_depart OWNER TO gtmsmanager;

--
-- Name: COLUMN sys_user_depart.id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_user_depart.id IS 'id';


--
-- Name: COLUMN sys_user_depart.user_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_user_depart.user_id IS '用户id';


--
-- Name: COLUMN sys_user_depart.dep_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_user_depart.dep_id IS '部门id';


--
-- Name: sys_user_password_history; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.sys_user_password_history (
    id character varying(32) NOT NULL,
    password character varying(255),
    create_time timestamp without time zone,
    salt character varying(45)
);


ALTER TABLE public.sys_user_password_history OWNER TO gtmsmanager;

--
-- Name: COLUMN sys_user_password_history.id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_user_password_history.id IS '用户id';


--
-- Name: COLUMN sys_user_password_history.password; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_user_password_history.password IS '密码';


--
-- Name: COLUMN sys_user_password_history.create_time; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_user_password_history.create_time IS '创建时间';


--
-- Name: sys_user_role; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.sys_user_role (
    id character varying(32) NOT NULL,
    user_id character varying(32),
    role_id character varying(32)
);


ALTER TABLE public.sys_user_role OWNER TO gtmsmanager;

--
-- Name: TABLE sys_user_role; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON TABLE public.sys_user_role IS '用户角色表';


--
-- Name: COLUMN sys_user_role.id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_user_role.id IS '主键id';


--
-- Name: COLUMN sys_user_role.user_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_user_role.user_id IS '用户id';


--
-- Name: COLUMN sys_user_role.role_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.sys_user_role.role_id IS '角色id';


--
-- Name: tab_acc_area; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_acc_area (
    area_id bigint NOT NULL,
    acc_oid bigint NOT NULL
);


ALTER TABLE public.tab_acc_area OWNER TO gtmsmanager;

--
-- Name: tab_alarm_record_id_seq; Type: SEQUENCE; Schema: public; Owner: gtmsmanager
--

CREATE SEQUENCE public.tab_alarm_record_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.tab_alarm_record_id_seq OWNER TO gtmsmanager;

--
-- Name: tab_alarm_record; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_alarm_record (
    id integer DEFAULT nextval('public.tab_alarm_record_id_seq'::regclass) NOT NULL,
    device_id character varying(64) NOT NULL,
    alarm_time integer NOT NULL,
    alarm_type integer NOT NULL,
    alarm_title character varying(100),
    alarm_content character varying(200) NOT NULL,
    status integer NOT NULL,
    confirm_time integer NOT NULL,
    alarm_content_zh character varying(200),
    alarm_content_es character varying(200),
    mac character varying(200),
    ipaddress character varying(200)
);


ALTER TABLE public.tab_alarm_record OWNER TO gtmsmanager;

--
-- Name: COLUMN tab_alarm_record.alarm_type; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_alarm_record.alarm_type IS '1- new device connects to the Wi-Fi;2-signal strength drops';


--
-- Name: COLUMN tab_alarm_record.status; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_alarm_record.status IS '0-active;1-cleared;';


--
-- Name: tab_app_sign_config_id_seq; Type: SEQUENCE; Schema: public; Owner: gtmsmanager
--

CREATE SEQUENCE public.tab_app_sign_config_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.tab_app_sign_config_id_seq OWNER TO gtmsmanager;

--
-- Name: tab_app_sign_config; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_app_sign_config (
    id integer DEFAULT nextval('public.tab_app_sign_config_id_seq'::regclass) NOT NULL,
    app_key character varying(64) NOT NULL,
    app_id character varying(64) NOT NULL,
    app_secret character varying(64) NOT NULL,
    iv character varying(64) NOT NULL
);


ALTER TABLE public.tab_app_sign_config OWNER TO gtmsmanager;

--
-- Name: COLUMN tab_app_sign_config.app_secret; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_app_sign_config.app_secret IS '密钥';


--
-- Name: COLUMN tab_app_sign_config.iv; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_app_sign_config.iv IS '偏移量';


--
-- Name: tab_area; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_area (
    area_id numeric(10,0) NOT NULL,
    area_name character varying(30) NOT NULL,
    area_pid numeric(10,0),
    area_rootid numeric(10,0),
    area_layer numeric(2,0),
    acc_oid numeric(10,0),
    remark character varying(200)
);


ALTER TABLE public.tab_area OWNER TO gtmsmanager;

--
-- Name: tab_attach_devlist_id_seq; Type: SEQUENCE; Schema: public; Owner: gtmsmanager
--

CREATE SEQUENCE public.tab_attach_devlist_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.tab_attach_devlist_id_seq OWNER TO gtmsmanager;

--
-- Name: tab_attach_devlist; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_attach_devlist (
    id integer DEFAULT nextval('public.tab_attach_devlist_id_seq'::regclass) NOT NULL,
    device_id character varying(64) NOT NULL,
    ssid character varying(64),
    gather_time integer NOT NULL,
    attache_mac character varying(64) NOT NULL,
    bssid character varying(64)
);


ALTER TABLE public.tab_attach_devlist OWNER TO gtmsmanager;

--
-- Name: tab_auth; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_auth (
    gather_id character varying(10) NOT NULL,
    access_flag character varying(2) NOT NULL
);


ALTER TABLE public.tab_auth OWNER TO gtmsmanager;

--
-- Name: COLUMN tab_auth.access_flag; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_auth.access_flag IS '-1:不认证
0：BASIC
1:DIAGEST';


--
-- Name: tab_batch_task_dev; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_batch_task_dev (
    task_id character varying(50) NOT NULL,
    device_id character varying(50) NOT NULL,
    status integer DEFAULT 0,
    fault_code character varying(20),
    fault_desc text,
    result text,
    add_time integer NOT NULL,
    update_time integer NOT NULL
);


ALTER TABLE public.tab_batch_task_dev OWNER TO gtmsmanager;

--
-- Name: COLUMN tab_batch_task_dev.status; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_batch_task_dev.status IS '0-未做；1-执行中；2-执行成功；-1-执行失败；-2-白名单过滤';


--
-- Name: COLUMN tab_batch_task_dev.fault_code; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_batch_task_dev.fault_code IS '失败编码';


--
-- Name: COLUMN tab_batch_task_dev.fault_desc; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_batch_task_dev.fault_desc IS '失败原因描述';


--
-- Name: COLUMN tab_batch_task_dev.result; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_batch_task_dev.result IS '执行结果，比如ping测试记录测试结果，jsonobject格式存储';


--
-- Name: tab_batch_task_info; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_batch_task_info (
    task_id character varying(50) NOT NULL,
    task_status integer DEFAULT 0 NOT NULL,
    task_name character varying(50) NOT NULL,
    task_type integer DEFAULT 0 NOT NULL,
    operate_type integer DEFAULT 1 NOT NULL,
    task_dev_type integer DEFAULT 1 NOT NULL,
    import_data_id character varying(32),
    param_type character varying(10),
    dev_group_id character varying(32),
    process_num integer,
    maximum_minute integer,
    add_time integer NOT NULL,
    update_time integer NOT NULL,
    acc_oid integer,
    start_date character varying(32),
    end_date character varying(32),
    start_time character varying(32),
    end_time character varying(32),
    task_param text,
    is_filter_white integer DEFAULT 0,
    user_id character varying(32)
);


ALTER TABLE public.tab_batch_task_info OWNER TO gtmsmanager;

--
-- Name: COLUMN tab_batch_task_info.task_status; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_batch_task_info.task_status IS '0-未做；1-执行中;2-分发完成；3-执行完成；4-已激活';


--
-- Name: COLUMN tab_batch_task_info.task_type; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_batch_task_info.task_type IS '1-测速；2-重启；3-升级；4-ping；5-降级；6-配置恢复；7-参数修改；8-配置备份';


--
-- Name: COLUMN tab_batch_task_info.operate_type; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_batch_task_info.operate_type IS '触发方式，1-主动执行；2-被动执行';


--
-- Name: COLUMN tab_batch_task_info.task_dev_type; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_batch_task_info.task_dev_type IS '批量任务关联设备方式（1— 导入；2--分组；3—根据条件查询设备）';


--
-- Name: COLUMN tab_batch_task_info.import_data_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_batch_task_info.import_data_id IS '导入文件id';


--
-- Name: COLUMN tab_batch_task_info.param_type; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_batch_task_info.param_type IS '导入文件参数';


--
-- Name: COLUMN tab_batch_task_info.dev_group_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_batch_task_info.dev_group_id IS '关联设备分组';


--
-- Name: COLUMN tab_batch_task_info.process_num; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_batch_task_info.process_num IS '进程并发数';


--
-- Name: COLUMN tab_batch_task_info.maximum_minute; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_batch_task_info.maximum_minute IS '每分钟最大设备操作';


--
-- Name: COLUMN tab_batch_task_info.start_date; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_batch_task_info.start_date IS '任务开始日期yyyyMMdd';


--
-- Name: COLUMN tab_batch_task_info.end_date; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_batch_task_info.end_date IS '任务结束日期yyyyMMdd';


--
-- Name: COLUMN tab_batch_task_info.start_time; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_batch_task_info.start_time IS '任务开始时间HHmmss';


--
-- Name: COLUMN tab_batch_task_info.end_time; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_batch_task_info.end_time IS '任务结束时间HHmmss';


--
-- Name: COLUMN tab_batch_task_info.task_param; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_batch_task_info.task_param IS '任务参数，比如ping测试需要填写相关参数，采用jsonobject存储';


--
-- Name: COLUMN tab_batch_task_info.is_filter_white; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_batch_task_info.is_filter_white IS '是否过滤白名单，0-否；1-是';


--
-- Name: COLUMN tab_batch_task_info.user_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_batch_task_info.user_id IS '当前用户id';


--
-- Name: tab_batchgather_node; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_batchgather_node (
    loid character varying(20) NOT NULL,
    device_id character varying(20),
    node_info character varying(200),
    telnet_enable character varying(20),
    firewall_level character varying(10),
    deal_time numeric(10,0) NOT NULL,
    status numeric(2,0) NOT NULL
);


ALTER TABLE public.tab_batchgather_node OWNER TO gtmsmanager;

--
-- Name: COLUMN tab_batchgather_node.node_info; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_batchgather_node.node_info IS '采集的节点的名称及其值';


--
-- Name: COLUMN tab_batchgather_node.deal_time; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_batchgather_node.deal_time IS '当前更新时间戳';


--
-- Name: COLUMN tab_batchgather_node.status; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_batchgather_node.status IS '0:未采集
1：成功，
2：采集中，
-1：失败';


--
-- Name: tab_batchgettemplate_task; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_batchgettemplate_task (
    task_id integer NOT NULL,
    template_id bigint NOT NULL,
    task_name character varying(50) NOT NULL,
    add_time integer,
    task_status integer,
    querytype character varying(1) NOT NULL,
    device_id character varying(10),
    city_id character varying(20),
    vendor_id character varying(6),
    device_model_id character varying(4),
    devicetype_id integer,
    isbind character varying(2),
    file_name character varying(50),
    type integer,
    acc_oid integer,
    start_time integer,
    end_time integer,
    donow character varying(1)
);


ALTER TABLE public.tab_batchgettemplate_task OWNER TO gtmsmanager;

--
-- Name: TABLE tab_batchgettemplate_task; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON TABLE public.tab_batchgettemplate_task IS '批量参数获取任务表';


--
-- Name: COLUMN tab_batchgettemplate_task.task_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_batchgettemplate_task.task_id IS '任务id';


--
-- Name: COLUMN tab_batchgettemplate_task.template_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_batchgettemplate_task.template_id IS '模板id';


--
-- Name: COLUMN tab_batchgettemplate_task.task_name; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_batchgettemplate_task.task_name IS '任务名称';


--
-- Name: COLUMN tab_batchgettemplate_task.add_time; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_batchgettemplate_task.add_time IS '创建时间';


--
-- Name: COLUMN tab_batchgettemplate_task.task_status; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_batchgettemplate_task.task_status IS '任务状态：0未做，1.正常，2暂停，-1异常';


--
-- Name: COLUMN tab_batchgettemplate_task.querytype; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_batchgettemplate_task.querytype IS '查询类型 1：简单查询、2：高级查询、3：导入查询';


--
-- Name: COLUMN tab_batchgettemplate_task.device_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_batchgettemplate_task.device_id IS '设备id';


--
-- Name: COLUMN tab_batchgettemplate_task.city_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_batchgettemplate_task.city_id IS '属地id';


--
-- Name: COLUMN tab_batchgettemplate_task.vendor_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_batchgettemplate_task.vendor_id IS '厂商id';


--
-- Name: COLUMN tab_batchgettemplate_task.device_model_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_batchgettemplate_task.device_model_id IS '设备型号id';


--
-- Name: COLUMN tab_batchgettemplate_task.devicetype_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_batchgettemplate_task.devicetype_id IS '设备类型id';


--
-- Name: COLUMN tab_batchgettemplate_task.isbind; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_batchgettemplate_task.isbind IS '是否绑定';


--
-- Name: COLUMN tab_batchgettemplate_task.file_name; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_batchgettemplate_task.file_name IS '文件名';


--
-- Name: COLUMN tab_batchgettemplate_task.type; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_batchgettemplate_task.type IS '触发方式 2：周期上报、4：下次连接到系统、1：重新启动、6：参数改变';


--
-- Name: COLUMN tab_batchgettemplate_task.acc_oid; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_batchgettemplate_task.acc_oid IS '创建者id';


--
-- Name: COLUMN tab_batchgettemplate_task.start_time; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_batchgettemplate_task.start_time IS '任务开始时间';


--
-- Name: COLUMN tab_batchgettemplate_task.end_time; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_batchgettemplate_task.end_time IS '任务结束时间';


--
-- Name: COLUMN tab_batchgettemplate_task.donow; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_batchgettemplate_task.donow IS '触发方式 1：主动触发、0：按照type字段';


--
-- Name: tab_batchhttp_task; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_batchhttp_task (
    task_name character varying(100) NOT NULL,
    task_id numeric(14,0) NOT NULL,
    acc_oid numeric(14,0) NOT NULL,
    add_time numeric(10,0) NOT NULL,
    task_status numeric(1,0) NOT NULL,
    http_url character varying(100) NOT NULL,
    report_url character varying(100) NOT NULL,
    sql text,
    filepath text,
    city_id character varying(20),
    online_status numeric(1,0),
    vendor_id character varying(6),
    device_model_id character varying(4),
    devicetype_id numeric(4,0),
    cpe_allocatedstatus numeric(1,0),
    device_serialnumber character varying(64)
);


ALTER TABLE public.tab_batchhttp_task OWNER TO gtmsmanager;

--
-- Name: tab_batchhttp_task_dev; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_batchhttp_task_dev (
    task_id numeric(14,0) NOT NULL,
    device_id character varying(10) NOT NULL,
    oui character varying(6) NOT NULL,
    device_serialnumber character varying(64) NOT NULL,
    status numeric(6,0) NOT NULL,
    add_time numeric(10,0) NOT NULL,
    update_time numeric(10,0),
    city_id character varying(20) NOT NULL,
    wan_type numeric(2,0),
    pppoe_name character varying(40)
);


ALTER TABLE public.tab_batchhttp_task_dev OWNER TO gtmsmanager;

--
-- Name: tab_batchrestart_period; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_batchrestart_period (
    type numeric(65,30) NOT NULL,
    period numeric(2,0) NOT NULL,
    days numeric(4,0) NOT NULL
);


ALTER TABLE public.tab_batchrestart_period OWNER TO gtmsmanager;

--
-- Name: tab_batchsettemplate_dev; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_batchsettemplate_dev (
    task_id integer NOT NULL,
    device_id character varying(10) NOT NULL,
    "time" integer,
    status integer
);


ALTER TABLE public.tab_batchsettemplate_dev OWNER TO gtmsmanager;

--
-- Name: COLUMN tab_batchsettemplate_dev.task_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_batchsettemplate_dev.task_id IS '任务id';


--
-- Name: COLUMN tab_batchsettemplate_dev.device_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_batchsettemplate_dev.device_id IS '设备id';


--
-- Name: COLUMN tab_batchsettemplate_dev."time"; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_batchsettemplate_dev."time" IS '执行时间';


--
-- Name: COLUMN tab_batchsettemplate_dev.status; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_batchsettemplate_dev.status IS '执行状态：0未做，1成功，7暂停';


--
-- Name: tab_batchsettemplate_task; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_batchsettemplate_task (
    task_id integer NOT NULL,
    template_id bigint NOT NULL,
    task_name character varying(50) NOT NULL,
    add_time integer,
    task_status integer,
    querytype character varying(1) NOT NULL,
    device_id character varying(10),
    city_id character varying(20),
    vendor_id character varying(6),
    device_model_id character varying(4),
    devicetype_id integer,
    isbind character varying(2),
    file_name character varying(50),
    type integer,
    acc_oid integer,
    start_time integer,
    end_time integer,
    donow character varying(1)
);


ALTER TABLE public.tab_batchsettemplate_task OWNER TO gtmsmanager;

--
-- Name: COLUMN tab_batchsettemplate_task.task_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_batchsettemplate_task.task_id IS '任务id';


--
-- Name: COLUMN tab_batchsettemplate_task.template_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_batchsettemplate_task.template_id IS '模板id';


--
-- Name: COLUMN tab_batchsettemplate_task.task_name; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_batchsettemplate_task.task_name IS '任务名称';


--
-- Name: COLUMN tab_batchsettemplate_task.add_time; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_batchsettemplate_task.add_time IS '创建时间';


--
-- Name: COLUMN tab_batchsettemplate_task.task_status; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_batchsettemplate_task.task_status IS '任务状态：0未做，1.正常，2暂停，-1异常';


--
-- Name: COLUMN tab_batchsettemplate_task.querytype; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_batchsettemplate_task.querytype IS '查询类型 1：简单查询、2：高级查询、3：导入查询';


--
-- Name: COLUMN tab_batchsettemplate_task.device_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_batchsettemplate_task.device_id IS '设备id';


--
-- Name: COLUMN tab_batchsettemplate_task.city_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_batchsettemplate_task.city_id IS '属地id';


--
-- Name: COLUMN tab_batchsettemplate_task.vendor_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_batchsettemplate_task.vendor_id IS '厂商id';


--
-- Name: COLUMN tab_batchsettemplate_task.device_model_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_batchsettemplate_task.device_model_id IS '设备型号id';


--
-- Name: COLUMN tab_batchsettemplate_task.devicetype_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_batchsettemplate_task.devicetype_id IS '设备类型id';


--
-- Name: COLUMN tab_batchsettemplate_task.isbind; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_batchsettemplate_task.isbind IS '是否绑定';


--
-- Name: COLUMN tab_batchsettemplate_task.file_name; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_batchsettemplate_task.file_name IS '文件名';


--
-- Name: COLUMN tab_batchsettemplate_task.type; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_batchsettemplate_task.type IS '触发方式 2：周期上报、4：下次连接到系统、1：重新启动、6：参数改变';


--
-- Name: COLUMN tab_batchsettemplate_task.acc_oid; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_batchsettemplate_task.acc_oid IS '创建者id';


--
-- Name: COLUMN tab_batchsettemplate_task.start_time; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_batchsettemplate_task.start_time IS '任务开始时间';


--
-- Name: COLUMN tab_batchsettemplate_task.end_time; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_batchsettemplate_task.end_time IS '任务结束时间';


--
-- Name: COLUMN tab_batchsettemplate_task.donow; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_batchsettemplate_task.donow IS '触发方式 1：主动触发、0：按照type字段';


--
-- Name: tab_batchspeed_result_temp; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_batchspeed_result_temp (
    id numeric(30,0) NOT NULL,
    devsn character varying(64),
    pppoename character varying(64),
    pppoeip character varying(64),
    aspeed character varying(64),
    bspeed character varying(64),
    maxspeed character varying(64),
    rate character varying(64),
    starttime character varying(64),
    endtime character varying(64),
    diagnosticsstate character varying(64),
    testtime character varying(64),
    result character varying(64)
);


ALTER TABLE public.tab_batchspeed_result_temp OWNER TO gtmsmanager;

--
-- Name: COLUMN tab_batchspeed_result_temp.pppoename; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_batchspeed_result_temp.pppoename IS '��������';


--
-- Name: COLUMN tab_batchspeed_result_temp.pppoeip; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_batchspeed_result_temp.pppoeip IS '����IP';


--
-- Name: COLUMN tab_batchspeed_result_temp.aspeed; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_batchspeed_result_temp.aspeed IS '��������';


--
-- Name: COLUMN tab_batchspeed_result_temp.bspeed; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_batchspeed_result_temp.bspeed IS '��������';


--
-- Name: COLUMN tab_batchspeed_result_temp.maxspeed; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_batchspeed_result_temp.maxspeed IS '��������';


--
-- Name: COLUMN tab_batchspeed_result_temp.rate; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_batchspeed_result_temp.rate IS '����';


--
-- Name: COLUMN tab_batchspeed_result_temp.starttime; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_batchspeed_result_temp.starttime IS '��������';


--
-- Name: COLUMN tab_batchspeed_result_temp.endtime; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_batchspeed_result_temp.endtime IS '��������';


--
-- Name: COLUMN tab_batchspeed_result_temp.diagnosticsstate; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_batchspeed_result_temp.diagnosticsstate IS '��������';


--
-- Name: COLUMN tab_batchspeed_result_temp.testtime; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_batchspeed_result_temp.testtime IS '��������';


--
-- Name: tab_batchspeedcheck_temp; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_batchspeedcheck_temp (
    device_serialnumber character varying(64) NOT NULL
);


ALTER TABLE public.tab_batchspeedcheck_temp OWNER TO gtmsmanager;

--
-- Name: tab_bind_fail; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_bind_fail (
    username character varying(20),
    start_time numeric(20,0),
    fail_code character varying(20),
    fail_desc character varying(200),
    client_id character varying(20),
    thread_id character varying(20),
    device_id character varying(20)
);


ALTER TABLE public.tab_bind_fail OWNER TO gtmsmanager;

--
-- Name: tab_black_ip; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_black_ip (
    id integer NOT NULL,
    ip character varying(64) NOT NULL,
    source_type smallint DEFAULT 0 NOT NULL,
    black_type smallint DEFAULT 0 NOT NULL,
    create_time timestamp without time zone NOT NULL
);


ALTER TABLE public.tab_black_ip OWNER TO gtmsmanager;

--
-- Name: COLUMN tab_black_ip.source_type; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_black_ip.source_type IS '来源（0：网关限流加入黑名单；1：acs限流加入黑名单；2：手动加入黑名单；）';


--
-- Name: COLUMN tab_black_ip.black_type; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_black_ip.black_type IS '黑名单类型（0：限流；1：后续类型依次扩展）';


--
-- Name: tab_blacklist_task; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_blacklist_task (
    task_name character varying(100) NOT NULL,
    task_id numeric(14,0) NOT NULL,
    acc_oid numeric(14,0) NOT NULL,
    task_desc character varying(64),
    add_time numeric(10,0) NOT NULL,
    task_status numeric(1,0) NOT NULL,
    sql text,
    filepath text
);


ALTER TABLE public.tab_blacklist_task OWNER TO gtmsmanager;

--
-- Name: tab_boot_event; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_boot_event (
    device_id character varying(32) NOT NULL,
    deal_time numeric(10,0) NOT NULL,
    event_code character varying(32) NOT NULL,
    reboot_status numeric(2,0) NOT NULL
);


ALTER TABLE public.tab_boot_event OWNER TO gtmsmanager;

--
-- Name: tab_broad_band_param; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_broad_band_param (
    user_id numeric(10,0) NOT NULL,
    username character varying(40) NOT NULL,
    serv_type_id numeric(4,0) NOT NULL,
    ipoe_upbandwidth numeric(10,0),
    ipoe_downbandwidth numeric(10,0),
    ipoe_dscp numeric(10,0),
    app_type character varying(100),
    open_status numeric(1,0),
    updatetime numeric(10,0)
);


ALTER TABLE public.tab_broad_band_param OWNER TO gtmsmanager;

--
-- Name: COLUMN tab_broad_band_param.ipoe_upbandwidth; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_broad_band_param.ipoe_upbandwidth IS '基于WAN接口限速(上行):InternetGatewayDevice.WANDevice.1.WANConnectionDevice.{i}.WANIPConnection.{i}.X_CT-COM_SpeedLimit_UP';


--
-- Name: COLUMN tab_broad_band_param.ipoe_downbandwidth; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_broad_band_param.ipoe_downbandwidth IS '基于WAN接口限速(下行):InternetGatewayDevice.WANDevice.1.WANConnectionDevice.{i}.WANIPConnection.{i}.X_CT-COM_SpeedLimit_Down';


--
-- Name: COLUMN tab_broad_band_param.ipoe_dscp; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_broad_band_param.ipoe_dscp IS 'Qos配置上行DSCP值:InternetGatewayDevice.X_CT-COM_UplinkQoS.Classification.{i}.DSCPMarkValue';


--
-- Name: COLUMN tab_broad_band_param.app_type; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_broad_band_param.app_type IS '01：家庭云盘； 02：云游戏； 03：云 VR';


--
-- Name: COLUMN tab_broad_band_param.open_status; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_broad_band_param.open_status IS '0：未做,1：成功,-1:失败';


--
-- Name: tab_broad_band_router; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_broad_band_router (
    router_id numeric(10,0) NOT NULL,
    city_id character varying(20) NOT NULL,
    lan_id character varying(20),
    v4router_list text,
    v6router_list text,
    app_type character varying(30)
);


ALTER TABLE public.tab_broad_band_router OWNER TO gtmsmanager;

--
-- Name: COLUMN tab_broad_band_router.lan_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_broad_band_router.lan_id IS '集团地市编码';


--
-- Name: COLUMN tab_broad_band_router.v4router_list; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_broad_band_router.v4router_list IS 'v4路由ip';


--
-- Name: COLUMN tab_broad_band_router.v6router_list; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_broad_band_router.v6router_list IS 'v6路由ip';


--
-- Name: COLUMN tab_broad_band_router.app_type; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_broad_band_router.app_type IS '业务类型CloudDisk CloudGame CloudVR';


--
-- Name: tab_bss_dev_port; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_bss_dev_port (
    id numeric(3,0) NOT NULL,
    spec_name character varying(25) NOT NULL,
    gw_type character varying(10) NOT NULL,
    access_type character varying(10),
    status numeric(1,0),
    lan_num numeric(2,0) NOT NULL,
    voice_num numeric(2,0) NOT NULL,
    wlan_num numeric(2,0) NOT NULL,
    spec_desc character varying(25)
);


ALTER TABLE public.tab_bss_dev_port OWNER TO gtmsmanager;

--
-- Name: tab_bss_sheet; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_bss_sheet (
    bss_sheet_id character varying(50) NOT NULL,
    customer_id character varying(40),
    username character varying(50) NOT NULL,
    product_spec_id smallint NOT NULL,
    city_id character varying(20) NOT NULL,
    type smallint NOT NULL,
    order_type integer,
    receive_date bigint NOT NULL,
    result smallint,
    bind_state smallint DEFAULT 0 NOT NULL,
    bind_time bigint,
    result_spec_state smallint DEFAULT '-1'::integer NOT NULL,
    result_spec_time bigint,
    result_spec_desc character varying(200),
    remark character varying(200),
    servusername character varying(50),
    sheet_context character varying(4000) NOT NULL,
    returnt_context character varying(2000),
    gw_type smallint DEFAULT 1,
    order_remark character varying(50),
    order_no character varying(50),
    order_id character varying(50),
    order_self smallint,
    migration smallint,
    error_code character varying(100)
);


ALTER TABLE public.tab_bss_sheet OWNER TO gtmsmanager;

--
-- Name: tab_bss_sheet_bak; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_bss_sheet_bak (
    bss_sheet_id character varying(50) NOT NULL,
    customer_id character varying(40),
    username character varying(50) NOT NULL,
    product_spec_id numeric(4,0) NOT NULL,
    city_id character varying(20) NOT NULL,
    type numeric(4,0) NOT NULL,
    order_type numeric(6,0),
    receive_date numeric(16,0) NOT NULL,
    result numeric(1,0),
    bind_state numeric(1,0) NOT NULL,
    bind_time numeric(10,0),
    result_spec_state numeric(1,0) NOT NULL,
    result_spec_time numeric(10,0),
    result_spec_desc character varying(200),
    remark character varying(200),
    returnt_context text,
    gw_type numeric(1,0)
);


ALTER TABLE public.tab_bss_sheet_bak OWNER TO gtmsmanager;

--
-- Name: COLUMN tab_bss_sheet_bak.type; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_bss_sheet_bak.type IS '1: ���� 2: ���� 3: ���� 4: ���� 5: ����';


--
-- Name: COLUMN tab_bss_sheet_bak.order_type; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_bss_sheet_bak.order_type IS '1: ADSL
2: 普通LAN
3: 普通光纤
4: 专线LAN
5: 专线光纤
';


--
-- Name: COLUMN tab_bss_sheet_bak.result; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_bss_sheet_bak.result IS '具体见接口表
0：成功
1: 失败
';


--
-- Name: COLUMN tab_bss_sheet_bak.bind_state; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_bss_sheet_bak.bind_state IS '0：未绑定
1：已绑定
默认为0
';


--
-- Name: COLUMN tab_bss_sheet_bak.result_spec_state; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_bss_sheet_bak.result_spec_state IS '1-：未配置
0：失败
1：成功
默认-1
';


--
-- Name: tab_capacity_log; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_capacity_log (
    call_id integer NOT NULL,
    call_time integer,
    bind_account character varying(64),
    account_type integer,
    loid character varying(100),
    city_id character varying(20),
    cap_id integer,
    enname character varying(100),
    call_status integer,
    error_msg text,
    cost_time integer,
    call_date_sec integer,
    rpc_type character varying(255),
    device_type character varying(10),
    serial_number character varying(128)
)
PARTITION BY RANGE (call_time);


ALTER TABLE public.tab_capacity_log OWNER TO gtmsmanager;

--
-- Name: tab_capacity_log_bak_20260324121914; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_capacity_log_bak_20260324121914 (
    call_id integer NOT NULL,
    call_time integer,
    bind_account character varying(64),
    account_type integer,
    loid character varying(100),
    city_id character varying(20),
    cap_id integer,
    enname character varying(100),
    call_status integer,
    error_msg text,
    cost_time integer,
    call_date_sec integer,
    rpc_type character varying(255),
    device_type character varying(10),
    serial_number character varying
);


ALTER TABLE public.tab_capacity_log_bak_20260324121914 OWNER TO gtmsmanager;

--
-- Name: tab_capacity_log_default; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_capacity_log_default (
    call_id integer NOT NULL,
    call_time integer,
    bind_account character varying(64),
    account_type integer,
    loid character varying(100),
    city_id character varying(20),
    cap_id integer,
    enname character varying(100),
    call_status integer,
    error_msg text,
    cost_time integer,
    call_date_sec integer,
    rpc_type character varying(255),
    device_type character varying(10),
    serial_number character varying(128)
);


ALTER TABLE public.tab_capacity_log_default OWNER TO gtmsmanager;

--
-- Name: tab_capacity_log_p20260323; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_capacity_log_p20260323 (
    call_id integer NOT NULL,
    call_time integer,
    bind_account character varying(64),
    account_type integer,
    loid character varying(100),
    city_id character varying(20),
    cap_id integer,
    enname character varying(100),
    call_status integer,
    error_msg text,
    cost_time integer,
    call_date_sec integer,
    rpc_type character varying(255),
    device_type character varying(10),
    serial_number character varying(128)
);


ALTER TABLE public.tab_capacity_log_p20260323 OWNER TO gtmsmanager;

--
-- Name: tab_capacity_log_p20260324; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_capacity_log_p20260324 (
    call_id integer NOT NULL,
    call_time integer,
    bind_account character varying(64),
    account_type integer,
    loid character varying(100),
    city_id character varying(20),
    cap_id integer,
    enname character varying(100),
    call_status integer,
    error_msg text,
    cost_time integer,
    call_date_sec integer,
    rpc_type character varying(255),
    device_type character varying(10),
    serial_number character varying(128)
);


ALTER TABLE public.tab_capacity_log_p20260324 OWNER TO gtmsmanager;

--
-- Name: tab_capacity_log_p20260325; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_capacity_log_p20260325 (
    call_id integer NOT NULL,
    call_time integer,
    bind_account character varying(64),
    account_type integer,
    loid character varying(100),
    city_id character varying(20),
    cap_id integer,
    enname character varying(100),
    call_status integer,
    error_msg text,
    cost_time integer,
    call_date_sec integer,
    rpc_type character varying(255),
    device_type character varying(10),
    serial_number character varying(128)
);


ALTER TABLE public.tab_capacity_log_p20260325 OWNER TO gtmsmanager;

--
-- Name: tab_capacity_log_p20260326; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_capacity_log_p20260326 (
    call_id integer NOT NULL,
    call_time integer,
    bind_account character varying(64),
    account_type integer,
    loid character varying(100),
    city_id character varying(20),
    cap_id integer,
    enname character varying(100),
    call_status integer,
    error_msg text,
    cost_time integer,
    call_date_sec integer,
    rpc_type character varying(255),
    device_type character varying(10),
    serial_number character varying(128)
);


ALTER TABLE public.tab_capacity_log_p20260326 OWNER TO gtmsmanager;

--
-- Name: tab_capacity_log_p20260327; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_capacity_log_p20260327 (
    call_id integer NOT NULL,
    call_time integer,
    bind_account character varying(64),
    account_type integer,
    loid character varying(100),
    city_id character varying(20),
    cap_id integer,
    enname character varying(100),
    call_status integer,
    error_msg text,
    cost_time integer,
    call_date_sec integer,
    rpc_type character varying(255),
    device_type character varying(10),
    serial_number character varying(128)
);


ALTER TABLE public.tab_capacity_log_p20260327 OWNER TO gtmsmanager;

--
-- Name: tab_capacity_log_p20260328; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_capacity_log_p20260328 (
    call_id integer NOT NULL,
    call_time integer,
    bind_account character varying(64),
    account_type integer,
    loid character varying(100),
    city_id character varying(20),
    cap_id integer,
    enname character varying(100),
    call_status integer,
    error_msg text,
    cost_time integer,
    call_date_sec integer,
    rpc_type character varying(255),
    device_type character varying(10),
    serial_number character varying(128)
);


ALTER TABLE public.tab_capacity_log_p20260328 OWNER TO gtmsmanager;

--
-- Name: tab_capacity_log_p20260329; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_capacity_log_p20260329 (
    call_id integer NOT NULL,
    call_time integer,
    bind_account character varying(64),
    account_type integer,
    loid character varying(100),
    city_id character varying(20),
    cap_id integer,
    enname character varying(100),
    call_status integer,
    error_msg text,
    cost_time integer,
    call_date_sec integer,
    rpc_type character varying(255),
    device_type character varying(10),
    serial_number character varying(128)
);


ALTER TABLE public.tab_capacity_log_p20260329 OWNER TO gtmsmanager;

--
-- Name: tab_capacity_log_p20260330; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_capacity_log_p20260330 (
    call_id integer NOT NULL,
    call_time integer,
    bind_account character varying(64),
    account_type integer,
    loid character varying(100),
    city_id character varying(20),
    cap_id integer,
    enname character varying(100),
    call_status integer,
    error_msg text,
    cost_time integer,
    call_date_sec integer,
    rpc_type character varying(255),
    device_type character varying(10),
    serial_number character varying(128)
);


ALTER TABLE public.tab_capacity_log_p20260330 OWNER TO gtmsmanager;

--
-- Name: tab_capacity_log_p20260331; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_capacity_log_p20260331 (
    call_id integer NOT NULL,
    call_time integer,
    bind_account character varying(64),
    account_type integer,
    loid character varying(100),
    city_id character varying(20),
    cap_id integer,
    enname character varying(100),
    call_status integer,
    error_msg text,
    cost_time integer,
    call_date_sec integer,
    rpc_type character varying(255),
    device_type character varying(10),
    serial_number character varying(128)
);


ALTER TABLE public.tab_capacity_log_p20260331 OWNER TO gtmsmanager;

--
-- Name: tab_capacity_log_p20260401; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_capacity_log_p20260401 (
    call_id integer NOT NULL,
    call_time integer,
    bind_account character varying(64),
    account_type integer,
    loid character varying(100),
    city_id character varying(20),
    cap_id integer,
    enname character varying(100),
    call_status integer,
    error_msg text,
    cost_time integer,
    call_date_sec integer,
    rpc_type character varying(255),
    device_type character varying(10),
    serial_number character varying(128)
);


ALTER TABLE public.tab_capacity_log_p20260401 OWNER TO gtmsmanager;

--
-- Name: tab_capacity_log_p20260402; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_capacity_log_p20260402 (
    call_id integer NOT NULL,
    call_time integer,
    bind_account character varying(64),
    account_type integer,
    loid character varying(100),
    city_id character varying(20),
    cap_id integer,
    enname character varying(100),
    call_status integer,
    error_msg text,
    cost_time integer,
    call_date_sec integer,
    rpc_type character varying(255),
    device_type character varying(10),
    serial_number character varying(128)
);


ALTER TABLE public.tab_capacity_log_p20260402 OWNER TO gtmsmanager;

--
-- Name: tab_capacity_log_p20260403; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_capacity_log_p20260403 (
    call_id integer NOT NULL,
    call_time integer,
    bind_account character varying(64),
    account_type integer,
    loid character varying(100),
    city_id character varying(20),
    cap_id integer,
    enname character varying(100),
    call_status integer,
    error_msg text,
    cost_time integer,
    call_date_sec integer,
    rpc_type character varying(255),
    device_type character varying(10),
    serial_number character varying(128)
);


ALTER TABLE public.tab_capacity_log_p20260403 OWNER TO gtmsmanager;

--
-- Name: tab_capacity_log_p20260404; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_capacity_log_p20260404 (
    call_id integer NOT NULL,
    call_time integer,
    bind_account character varying(64),
    account_type integer,
    loid character varying(100),
    city_id character varying(20),
    cap_id integer,
    enname character varying(100),
    call_status integer,
    error_msg text,
    cost_time integer,
    call_date_sec integer,
    rpc_type character varying(255),
    device_type character varying(10),
    serial_number character varying(128)
);


ALTER TABLE public.tab_capacity_log_p20260404 OWNER TO gtmsmanager;

--
-- Name: tab_capacity_log_p20260405; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_capacity_log_p20260405 (
    call_id integer NOT NULL,
    call_time integer,
    bind_account character varying(64),
    account_type integer,
    loid character varying(100),
    city_id character varying(20),
    cap_id integer,
    enname character varying(100),
    call_status integer,
    error_msg text,
    cost_time integer,
    call_date_sec integer,
    rpc_type character varying(255),
    device_type character varying(10),
    serial_number character varying(128)
);


ALTER TABLE public.tab_capacity_log_p20260405 OWNER TO gtmsmanager;

--
-- Name: tab_capacity_log_p20260406; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_capacity_log_p20260406 (
    call_id integer NOT NULL,
    call_time integer,
    bind_account character varying(64),
    account_type integer,
    loid character varying(100),
    city_id character varying(20),
    cap_id integer,
    enname character varying(100),
    call_status integer,
    error_msg text,
    cost_time integer,
    call_date_sec integer,
    rpc_type character varying(255),
    device_type character varying(10),
    serial_number character varying(128)
);


ALTER TABLE public.tab_capacity_log_p20260406 OWNER TO gtmsmanager;

--
-- Name: tab_capacity_log_p20260407; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_capacity_log_p20260407 (
    call_id integer NOT NULL,
    call_time integer,
    bind_account character varying(64),
    account_type integer,
    loid character varying(100),
    city_id character varying(20),
    cap_id integer,
    enname character varying(100),
    call_status integer,
    error_msg text,
    cost_time integer,
    call_date_sec integer,
    rpc_type character varying(255),
    device_type character varying(10),
    serial_number character varying(128)
);


ALTER TABLE public.tab_capacity_log_p20260407 OWNER TO gtmsmanager;

--
-- Name: tab_capacity_log_p20260408; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_capacity_log_p20260408 (
    call_id integer NOT NULL,
    call_time integer,
    bind_account character varying(64),
    account_type integer,
    loid character varying(100),
    city_id character varying(20),
    cap_id integer,
    enname character varying(100),
    call_status integer,
    error_msg text,
    cost_time integer,
    call_date_sec integer,
    rpc_type character varying(255),
    device_type character varying(10),
    serial_number character varying(128)
);


ALTER TABLE public.tab_capacity_log_p20260408 OWNER TO gtmsmanager;

--
-- Name: tab_capacity_log_p20260409; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_capacity_log_p20260409 (
    call_id integer NOT NULL,
    call_time integer,
    bind_account character varying(64),
    account_type integer,
    loid character varying(100),
    city_id character varying(20),
    cap_id integer,
    enname character varying(100),
    call_status integer,
    error_msg text,
    cost_time integer,
    call_date_sec integer,
    rpc_type character varying(255),
    device_type character varying(10),
    serial_number character varying(128)
);


ALTER TABLE public.tab_capacity_log_p20260409 OWNER TO gtmsmanager;

--
-- Name: tab_capacity_log_p20260410; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_capacity_log_p20260410 (
    call_id integer NOT NULL,
    call_time integer,
    bind_account character varying(64),
    account_type integer,
    loid character varying(100),
    city_id character varying(20),
    cap_id integer,
    enname character varying(100),
    call_status integer,
    error_msg text,
    cost_time integer,
    call_date_sec integer,
    rpc_type character varying(255),
    device_type character varying(10),
    serial_number character varying(128)
);


ALTER TABLE public.tab_capacity_log_p20260410 OWNER TO gtmsmanager;

--
-- Name: tab_capacity_log_p20260411; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_capacity_log_p20260411 (
    call_id integer NOT NULL,
    call_time integer,
    bind_account character varying(64),
    account_type integer,
    loid character varying(100),
    city_id character varying(20),
    cap_id integer,
    enname character varying(100),
    call_status integer,
    error_msg text,
    cost_time integer,
    call_date_sec integer,
    rpc_type character varying(255),
    device_type character varying(10),
    serial_number character varying(128)
);


ALTER TABLE public.tab_capacity_log_p20260411 OWNER TO gtmsmanager;

--
-- Name: tab_capacity_log_p20260412; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_capacity_log_p20260412 (
    call_id integer NOT NULL,
    call_time integer,
    bind_account character varying(64),
    account_type integer,
    loid character varying(100),
    city_id character varying(20),
    cap_id integer,
    enname character varying(100),
    call_status integer,
    error_msg text,
    cost_time integer,
    call_date_sec integer,
    rpc_type character varying(255),
    device_type character varying(10),
    serial_number character varying(128)
);


ALTER TABLE public.tab_capacity_log_p20260412 OWNER TO gtmsmanager;

--
-- Name: tab_capacity_log_p20260413; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_capacity_log_p20260413 (
    call_id integer NOT NULL,
    call_time integer,
    bind_account character varying(64),
    account_type integer,
    loid character varying(100),
    city_id character varying(20),
    cap_id integer,
    enname character varying(100),
    call_status integer,
    error_msg text,
    cost_time integer,
    call_date_sec integer,
    rpc_type character varying(255),
    device_type character varying(10),
    serial_number character varying(128)
);


ALTER TABLE public.tab_capacity_log_p20260413 OWNER TO gtmsmanager;

--
-- Name: tab_capacity_log_p20260414; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_capacity_log_p20260414 (
    call_id integer NOT NULL,
    call_time integer,
    bind_account character varying(64),
    account_type integer,
    loid character varying(100),
    city_id character varying(20),
    cap_id integer,
    enname character varying(100),
    call_status integer,
    error_msg text,
    cost_time integer,
    call_date_sec integer,
    rpc_type character varying(255),
    device_type character varying(10),
    serial_number character varying(128)
);


ALTER TABLE public.tab_capacity_log_p20260414 OWNER TO gtmsmanager;

--
-- Name: tab_capacity_log_p20260415; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_capacity_log_p20260415 (
    call_id integer NOT NULL,
    call_time integer,
    bind_account character varying(64),
    account_type integer,
    loid character varying(100),
    city_id character varying(20),
    cap_id integer,
    enname character varying(100),
    call_status integer,
    error_msg text,
    cost_time integer,
    call_date_sec integer,
    rpc_type character varying(255),
    device_type character varying(10),
    serial_number character varying(128)
);


ALTER TABLE public.tab_capacity_log_p20260415 OWNER TO gtmsmanager;

--
-- Name: tab_capacity_log_p20260416; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_capacity_log_p20260416 (
    call_id integer NOT NULL,
    call_time integer,
    bind_account character varying(64),
    account_type integer,
    loid character varying(100),
    city_id character varying(20),
    cap_id integer,
    enname character varying(100),
    call_status integer,
    error_msg text,
    cost_time integer,
    call_date_sec integer,
    rpc_type character varying(255),
    device_type character varying(10),
    serial_number character varying(128)
);


ALTER TABLE public.tab_capacity_log_p20260416 OWNER TO gtmsmanager;

--
-- Name: tab_capacity_log_p20260417; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_capacity_log_p20260417 (
    call_id integer NOT NULL,
    call_time integer,
    bind_account character varying(64),
    account_type integer,
    loid character varying(100),
    city_id character varying(20),
    cap_id integer,
    enname character varying(100),
    call_status integer,
    error_msg text,
    cost_time integer,
    call_date_sec integer,
    rpc_type character varying(255),
    device_type character varying(10),
    serial_number character varying(128)
);


ALTER TABLE public.tab_capacity_log_p20260417 OWNER TO gtmsmanager;

--
-- Name: tab_capacity_log_p20260418; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_capacity_log_p20260418 (
    call_id integer NOT NULL,
    call_time integer,
    bind_account character varying(64),
    account_type integer,
    loid character varying(100),
    city_id character varying(20),
    cap_id integer,
    enname character varying(100),
    call_status integer,
    error_msg text,
    cost_time integer,
    call_date_sec integer,
    rpc_type character varying(255),
    device_type character varying(10),
    serial_number character varying(128)
);


ALTER TABLE public.tab_capacity_log_p20260418 OWNER TO gtmsmanager;

--
-- Name: tab_capacity_log_p20260419; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_capacity_log_p20260419 (
    call_id integer NOT NULL,
    call_time integer,
    bind_account character varying(64),
    account_type integer,
    loid character varying(100),
    city_id character varying(20),
    cap_id integer,
    enname character varying(100),
    call_status integer,
    error_msg text,
    cost_time integer,
    call_date_sec integer,
    rpc_type character varying(255),
    device_type character varying(10),
    serial_number character varying(128)
);


ALTER TABLE public.tab_capacity_log_p20260419 OWNER TO gtmsmanager;

--
-- Name: tab_capacity_log_p20260420; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_capacity_log_p20260420 (
    call_id integer NOT NULL,
    call_time integer,
    bind_account character varying(64),
    account_type integer,
    loid character varying(100),
    city_id character varying(20),
    cap_id integer,
    enname character varying(100),
    call_status integer,
    error_msg text,
    cost_time integer,
    call_date_sec integer,
    rpc_type character varying(255),
    device_type character varying(10),
    serial_number character varying(128)
);


ALTER TABLE public.tab_capacity_log_p20260420 OWNER TO gtmsmanager;

--
-- Name: tab_capacity_log_p20260421; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_capacity_log_p20260421 (
    call_id integer NOT NULL,
    call_time integer,
    bind_account character varying(64),
    account_type integer,
    loid character varying(100),
    city_id character varying(20),
    cap_id integer,
    enname character varying(100),
    call_status integer,
    error_msg text,
    cost_time integer,
    call_date_sec integer,
    rpc_type character varying(255),
    device_type character varying(10),
    serial_number character varying(128)
);


ALTER TABLE public.tab_capacity_log_p20260421 OWNER TO gtmsmanager;

--
-- Name: tab_capacity_log_p20260422; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_capacity_log_p20260422 (
    call_id integer NOT NULL,
    call_time integer,
    bind_account character varying(64),
    account_type integer,
    loid character varying(100),
    city_id character varying(20),
    cap_id integer,
    enname character varying(100),
    call_status integer,
    error_msg text,
    cost_time integer,
    call_date_sec integer,
    rpc_type character varying(255),
    device_type character varying(10),
    serial_number character varying(128)
);


ALTER TABLE public.tab_capacity_log_p20260422 OWNER TO gtmsmanager;

--
-- Name: tab_capacity_log_p20260423; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_capacity_log_p20260423 (
    call_id integer NOT NULL,
    call_time integer,
    bind_account character varying(64),
    account_type integer,
    loid character varying(100),
    city_id character varying(20),
    cap_id integer,
    enname character varying(100),
    call_status integer,
    error_msg text,
    cost_time integer,
    call_date_sec integer,
    rpc_type character varying(255),
    device_type character varying(10),
    serial_number character varying(128)
);


ALTER TABLE public.tab_capacity_log_p20260423 OWNER TO gtmsmanager;

--
-- Name: tab_capacity_log_parameter; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_capacity_log_parameter (
    call_id integer NOT NULL,
    call_time integer,
    in_parameter text COLLATE pg_catalog."C",
    out_parameter text COLLATE pg_catalog."C",
    real_parameter text COLLATE pg_catalog."C",
    real_resp text COLLATE pg_catalog."C"
)
PARTITION BY RANGE (call_time);


ALTER TABLE public.tab_capacity_log_parameter OWNER TO gtmsmanager;

--
-- Name: tab_capacity_log_parameter_bak_20260324121914; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_capacity_log_parameter_bak_20260324121914 (
    call_id integer NOT NULL,
    call_time integer,
    in_parameter text COLLATE pg_catalog."C",
    out_parameter text COLLATE pg_catalog."C",
    real_parameter text COLLATE pg_catalog."C",
    real_resp text COLLATE pg_catalog."C"
);


ALTER TABLE public.tab_capacity_log_parameter_bak_20260324121914 OWNER TO gtmsmanager;

--
-- Name: tab_capacity_log_parameter_default; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_capacity_log_parameter_default (
    call_id integer NOT NULL,
    call_time integer,
    in_parameter text COLLATE pg_catalog."C",
    out_parameter text COLLATE pg_catalog."C",
    real_parameter text COLLATE pg_catalog."C",
    real_resp text COLLATE pg_catalog."C"
);


ALTER TABLE public.tab_capacity_log_parameter_default OWNER TO gtmsmanager;

--
-- Name: tab_capacity_log_parameter_p20260323; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_capacity_log_parameter_p20260323 (
    call_id integer NOT NULL,
    call_time integer,
    in_parameter text COLLATE pg_catalog."C",
    out_parameter text COLLATE pg_catalog."C",
    real_parameter text COLLATE pg_catalog."C",
    real_resp text COLLATE pg_catalog."C"
);


ALTER TABLE public.tab_capacity_log_parameter_p20260323 OWNER TO gtmsmanager;

--
-- Name: tab_capacity_log_parameter_p20260324; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_capacity_log_parameter_p20260324 (
    call_id integer NOT NULL,
    call_time integer,
    in_parameter text COLLATE pg_catalog."C",
    out_parameter text COLLATE pg_catalog."C",
    real_parameter text COLLATE pg_catalog."C",
    real_resp text COLLATE pg_catalog."C"
);


ALTER TABLE public.tab_capacity_log_parameter_p20260324 OWNER TO gtmsmanager;

--
-- Name: tab_capacity_log_parameter_p20260325; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_capacity_log_parameter_p20260325 (
    call_id integer NOT NULL,
    call_time integer,
    in_parameter text COLLATE pg_catalog."C",
    out_parameter text COLLATE pg_catalog."C",
    real_parameter text COLLATE pg_catalog."C",
    real_resp text COLLATE pg_catalog."C"
);


ALTER TABLE public.tab_capacity_log_parameter_p20260325 OWNER TO gtmsmanager;

--
-- Name: tab_capacity_log_parameter_p20260326; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_capacity_log_parameter_p20260326 (
    call_id integer NOT NULL,
    call_time integer,
    in_parameter text COLLATE pg_catalog."C",
    out_parameter text COLLATE pg_catalog."C",
    real_parameter text COLLATE pg_catalog."C",
    real_resp text COLLATE pg_catalog."C"
);


ALTER TABLE public.tab_capacity_log_parameter_p20260326 OWNER TO gtmsmanager;

--
-- Name: tab_capacity_log_parameter_p20260327; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_capacity_log_parameter_p20260327 (
    call_id integer NOT NULL,
    call_time integer,
    in_parameter text COLLATE pg_catalog."C",
    out_parameter text COLLATE pg_catalog."C",
    real_parameter text COLLATE pg_catalog."C",
    real_resp text COLLATE pg_catalog."C"
);


ALTER TABLE public.tab_capacity_log_parameter_p20260327 OWNER TO gtmsmanager;

--
-- Name: tab_capacity_log_parameter_p20260328; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_capacity_log_parameter_p20260328 (
    call_id integer NOT NULL,
    call_time integer,
    in_parameter text COLLATE pg_catalog."C",
    out_parameter text COLLATE pg_catalog."C",
    real_parameter text COLLATE pg_catalog."C",
    real_resp text COLLATE pg_catalog."C"
);


ALTER TABLE public.tab_capacity_log_parameter_p20260328 OWNER TO gtmsmanager;

--
-- Name: tab_capacity_log_parameter_p20260329; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_capacity_log_parameter_p20260329 (
    call_id integer NOT NULL,
    call_time integer,
    in_parameter text COLLATE pg_catalog."C",
    out_parameter text COLLATE pg_catalog."C",
    real_parameter text COLLATE pg_catalog."C",
    real_resp text COLLATE pg_catalog."C"
);


ALTER TABLE public.tab_capacity_log_parameter_p20260329 OWNER TO gtmsmanager;

--
-- Name: tab_capacity_log_parameter_p20260330; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_capacity_log_parameter_p20260330 (
    call_id integer NOT NULL,
    call_time integer,
    in_parameter text COLLATE pg_catalog."C",
    out_parameter text COLLATE pg_catalog."C",
    real_parameter text COLLATE pg_catalog."C",
    real_resp text COLLATE pg_catalog."C"
);


ALTER TABLE public.tab_capacity_log_parameter_p20260330 OWNER TO gtmsmanager;

--
-- Name: tab_capacity_log_parameter_p20260331; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_capacity_log_parameter_p20260331 (
    call_id integer NOT NULL,
    call_time integer,
    in_parameter text COLLATE pg_catalog."C",
    out_parameter text COLLATE pg_catalog."C",
    real_parameter text COLLATE pg_catalog."C",
    real_resp text COLLATE pg_catalog."C"
);


ALTER TABLE public.tab_capacity_log_parameter_p20260331 OWNER TO gtmsmanager;

--
-- Name: tab_capacity_log_parameter_p20260401; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_capacity_log_parameter_p20260401 (
    call_id integer NOT NULL,
    call_time integer,
    in_parameter text COLLATE pg_catalog."C",
    out_parameter text COLLATE pg_catalog."C",
    real_parameter text COLLATE pg_catalog."C",
    real_resp text COLLATE pg_catalog."C"
);


ALTER TABLE public.tab_capacity_log_parameter_p20260401 OWNER TO gtmsmanager;

--
-- Name: tab_capacity_log_parameter_p20260402; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_capacity_log_parameter_p20260402 (
    call_id integer NOT NULL,
    call_time integer,
    in_parameter text COLLATE pg_catalog."C",
    out_parameter text COLLATE pg_catalog."C",
    real_parameter text COLLATE pg_catalog."C",
    real_resp text COLLATE pg_catalog."C"
);


ALTER TABLE public.tab_capacity_log_parameter_p20260402 OWNER TO gtmsmanager;

--
-- Name: tab_capacity_log_parameter_p20260403; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_capacity_log_parameter_p20260403 (
    call_id integer NOT NULL,
    call_time integer,
    in_parameter text COLLATE pg_catalog."C",
    out_parameter text COLLATE pg_catalog."C",
    real_parameter text COLLATE pg_catalog."C",
    real_resp text COLLATE pg_catalog."C"
);


ALTER TABLE public.tab_capacity_log_parameter_p20260403 OWNER TO gtmsmanager;

--
-- Name: tab_capacity_log_parameter_p20260404; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_capacity_log_parameter_p20260404 (
    call_id integer NOT NULL,
    call_time integer,
    in_parameter text COLLATE pg_catalog."C",
    out_parameter text COLLATE pg_catalog."C",
    real_parameter text COLLATE pg_catalog."C",
    real_resp text COLLATE pg_catalog."C"
);


ALTER TABLE public.tab_capacity_log_parameter_p20260404 OWNER TO gtmsmanager;

--
-- Name: tab_capacity_log_parameter_p20260405; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_capacity_log_parameter_p20260405 (
    call_id integer NOT NULL,
    call_time integer,
    in_parameter text COLLATE pg_catalog."C",
    out_parameter text COLLATE pg_catalog."C",
    real_parameter text COLLATE pg_catalog."C",
    real_resp text COLLATE pg_catalog."C"
);


ALTER TABLE public.tab_capacity_log_parameter_p20260405 OWNER TO gtmsmanager;

--
-- Name: tab_capacity_log_parameter_p20260406; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_capacity_log_parameter_p20260406 (
    call_id integer NOT NULL,
    call_time integer,
    in_parameter text COLLATE pg_catalog."C",
    out_parameter text COLLATE pg_catalog."C",
    real_parameter text COLLATE pg_catalog."C",
    real_resp text COLLATE pg_catalog."C"
);


ALTER TABLE public.tab_capacity_log_parameter_p20260406 OWNER TO gtmsmanager;

--
-- Name: tab_capacity_log_parameter_p20260407; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_capacity_log_parameter_p20260407 (
    call_id integer NOT NULL,
    call_time integer,
    in_parameter text COLLATE pg_catalog."C",
    out_parameter text COLLATE pg_catalog."C",
    real_parameter text COLLATE pg_catalog."C",
    real_resp text COLLATE pg_catalog."C"
);


ALTER TABLE public.tab_capacity_log_parameter_p20260407 OWNER TO gtmsmanager;

--
-- Name: tab_capacity_log_parameter_p20260408; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_capacity_log_parameter_p20260408 (
    call_id integer NOT NULL,
    call_time integer,
    in_parameter text COLLATE pg_catalog."C",
    out_parameter text COLLATE pg_catalog."C",
    real_parameter text COLLATE pg_catalog."C",
    real_resp text COLLATE pg_catalog."C"
);


ALTER TABLE public.tab_capacity_log_parameter_p20260408 OWNER TO gtmsmanager;

--
-- Name: tab_capacity_log_parameter_p20260409; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_capacity_log_parameter_p20260409 (
    call_id integer NOT NULL,
    call_time integer,
    in_parameter text COLLATE pg_catalog."C",
    out_parameter text COLLATE pg_catalog."C",
    real_parameter text COLLATE pg_catalog."C",
    real_resp text COLLATE pg_catalog."C"
);


ALTER TABLE public.tab_capacity_log_parameter_p20260409 OWNER TO gtmsmanager;

--
-- Name: tab_capacity_log_parameter_p20260410; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_capacity_log_parameter_p20260410 (
    call_id integer NOT NULL,
    call_time integer,
    in_parameter text COLLATE pg_catalog."C",
    out_parameter text COLLATE pg_catalog."C",
    real_parameter text COLLATE pg_catalog."C",
    real_resp text COLLATE pg_catalog."C"
);


ALTER TABLE public.tab_capacity_log_parameter_p20260410 OWNER TO gtmsmanager;

--
-- Name: tab_capacity_log_parameter_p20260411; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_capacity_log_parameter_p20260411 (
    call_id integer NOT NULL,
    call_time integer,
    in_parameter text COLLATE pg_catalog."C",
    out_parameter text COLLATE pg_catalog."C",
    real_parameter text COLLATE pg_catalog."C",
    real_resp text COLLATE pg_catalog."C"
);


ALTER TABLE public.tab_capacity_log_parameter_p20260411 OWNER TO gtmsmanager;

--
-- Name: tab_capacity_log_parameter_p20260412; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_capacity_log_parameter_p20260412 (
    call_id integer NOT NULL,
    call_time integer,
    in_parameter text COLLATE pg_catalog."C",
    out_parameter text COLLATE pg_catalog."C",
    real_parameter text COLLATE pg_catalog."C",
    real_resp text COLLATE pg_catalog."C"
);


ALTER TABLE public.tab_capacity_log_parameter_p20260412 OWNER TO gtmsmanager;

--
-- Name: tab_capacity_log_parameter_p20260413; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_capacity_log_parameter_p20260413 (
    call_id integer NOT NULL,
    call_time integer,
    in_parameter text COLLATE pg_catalog."C",
    out_parameter text COLLATE pg_catalog."C",
    real_parameter text COLLATE pg_catalog."C",
    real_resp text COLLATE pg_catalog."C"
);


ALTER TABLE public.tab_capacity_log_parameter_p20260413 OWNER TO gtmsmanager;

--
-- Name: tab_capacity_log_parameter_p20260414; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_capacity_log_parameter_p20260414 (
    call_id integer NOT NULL,
    call_time integer,
    in_parameter text COLLATE pg_catalog."C",
    out_parameter text COLLATE pg_catalog."C",
    real_parameter text COLLATE pg_catalog."C",
    real_resp text COLLATE pg_catalog."C"
);


ALTER TABLE public.tab_capacity_log_parameter_p20260414 OWNER TO gtmsmanager;

--
-- Name: tab_capacity_log_parameter_p20260415; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_capacity_log_parameter_p20260415 (
    call_id integer NOT NULL,
    call_time integer,
    in_parameter text COLLATE pg_catalog."C",
    out_parameter text COLLATE pg_catalog."C",
    real_parameter text COLLATE pg_catalog."C",
    real_resp text COLLATE pg_catalog."C"
);


ALTER TABLE public.tab_capacity_log_parameter_p20260415 OWNER TO gtmsmanager;

--
-- Name: tab_capacity_log_parameter_p20260416; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_capacity_log_parameter_p20260416 (
    call_id integer NOT NULL,
    call_time integer,
    in_parameter text COLLATE pg_catalog."C",
    out_parameter text COLLATE pg_catalog."C",
    real_parameter text COLLATE pg_catalog."C",
    real_resp text COLLATE pg_catalog."C"
);


ALTER TABLE public.tab_capacity_log_parameter_p20260416 OWNER TO gtmsmanager;

--
-- Name: tab_capacity_log_parameter_p20260417; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_capacity_log_parameter_p20260417 (
    call_id integer NOT NULL,
    call_time integer,
    in_parameter text COLLATE pg_catalog."C",
    out_parameter text COLLATE pg_catalog."C",
    real_parameter text COLLATE pg_catalog."C",
    real_resp text COLLATE pg_catalog."C"
);


ALTER TABLE public.tab_capacity_log_parameter_p20260417 OWNER TO gtmsmanager;

--
-- Name: tab_capacity_log_parameter_p20260418; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_capacity_log_parameter_p20260418 (
    call_id integer NOT NULL,
    call_time integer,
    in_parameter text COLLATE pg_catalog."C",
    out_parameter text COLLATE pg_catalog."C",
    real_parameter text COLLATE pg_catalog."C",
    real_resp text COLLATE pg_catalog."C"
);


ALTER TABLE public.tab_capacity_log_parameter_p20260418 OWNER TO gtmsmanager;

--
-- Name: tab_capacity_log_parameter_p20260419; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_capacity_log_parameter_p20260419 (
    call_id integer NOT NULL,
    call_time integer,
    in_parameter text COLLATE pg_catalog."C",
    out_parameter text COLLATE pg_catalog."C",
    real_parameter text COLLATE pg_catalog."C",
    real_resp text COLLATE pg_catalog."C"
);


ALTER TABLE public.tab_capacity_log_parameter_p20260419 OWNER TO gtmsmanager;

--
-- Name: tab_capacity_log_parameter_p20260420; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_capacity_log_parameter_p20260420 (
    call_id integer NOT NULL,
    call_time integer,
    in_parameter text COLLATE pg_catalog."C",
    out_parameter text COLLATE pg_catalog."C",
    real_parameter text COLLATE pg_catalog."C",
    real_resp text COLLATE pg_catalog."C"
);


ALTER TABLE public.tab_capacity_log_parameter_p20260420 OWNER TO gtmsmanager;

--
-- Name: tab_capacity_log_parameter_p20260421; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_capacity_log_parameter_p20260421 (
    call_id integer NOT NULL,
    call_time integer,
    in_parameter text COLLATE pg_catalog."C",
    out_parameter text COLLATE pg_catalog."C",
    real_parameter text COLLATE pg_catalog."C",
    real_resp text COLLATE pg_catalog."C"
);


ALTER TABLE public.tab_capacity_log_parameter_p20260421 OWNER TO gtmsmanager;

--
-- Name: tab_capacity_log_parameter_p20260422; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_capacity_log_parameter_p20260422 (
    call_id integer NOT NULL,
    call_time integer,
    in_parameter text COLLATE pg_catalog."C",
    out_parameter text COLLATE pg_catalog."C",
    real_parameter text COLLATE pg_catalog."C",
    real_resp text COLLATE pg_catalog."C"
);


ALTER TABLE public.tab_capacity_log_parameter_p20260422 OWNER TO gtmsmanager;

--
-- Name: tab_capacity_log_parameter_p20260423; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_capacity_log_parameter_p20260423 (
    call_id integer NOT NULL,
    call_time integer,
    in_parameter text COLLATE pg_catalog."C",
    out_parameter text COLLATE pg_catalog."C",
    real_parameter text COLLATE pg_catalog."C",
    real_resp text COLLATE pg_catalog."C"
);


ALTER TABLE public.tab_capacity_log_parameter_p20260423 OWNER TO gtmsmanager;

--
-- Name: tab_capacity_log_parameter_tapdata_id_seq; Type: SEQUENCE; Schema: public; Owner: gtmsmanager
--

CREATE SEQUENCE public.tab_capacity_log_parameter_tapdata_id_seq
    START WITH 3527
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 2147483647
    CACHE 1;


ALTER SEQUENCE public.tab_capacity_log_parameter_tapdata_id_seq OWNER TO gtmsmanager;

--
-- Name: tab_capacity_log_parameter_zss; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_capacity_log_parameter_zss (
    call_id integer,
    call_time integer,
    in_parameter text COLLATE pg_catalog."C",
    out_parameter text COLLATE pg_catalog."C",
    real_parameter text COLLATE pg_catalog."C",
    real_resp text COLLATE pg_catalog."C"
);


ALTER TABLE public.tab_capacity_log_parameter_zss OWNER TO gtmsmanager;

--
-- Name: tab_capacity_log_zss; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_capacity_log_zss (
    call_id integer,
    call_time integer,
    bind_account character varying(64),
    account_type integer,
    loid character varying(100),
    city_id character varying(20),
    cap_id integer,
    enname character varying(100),
    call_status integer,
    error_msg text,
    cost_time integer,
    call_date_sec integer,
    rpc_type character varying(255),
    device_type character varying(10)
);


ALTER TABLE public.tab_capacity_log_zss OWNER TO gtmsmanager;

--
-- Name: tab_city; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_city (
    city_id character varying(20) NOT NULL,
    parent_id character varying(20),
    city_name character varying(50) NOT NULL,
    staff_id character varying(30),
    remark character varying(100),
    sequ numeric(5,0) DEFAULT 0 NOT NULL,
    level smallint
);


ALTER TABLE public.tab_city OWNER TO gtmsmanager;

--
-- Name: COLUMN tab_city.level; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_city.level IS '层级';


--
-- Name: tab_city_area; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_city_area (
    city_id character varying(20) NOT NULL,
    area_id numeric(10,0) NOT NULL
);


ALTER TABLE public.tab_city_area OWNER TO gtmsmanager;

--
-- Name: tab_city_bak0905; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_city_bak0905 (
    city_id character varying(20) NOT NULL,
    parent_id character varying(20),
    city_name character varying(50) NOT NULL,
    staff_id character varying(30),
    remark character varying(100),
    sequ numeric(5,0) DEFAULT 0 NOT NULL,
    level smallint
);


ALTER TABLE public.tab_city_bak0905 OWNER TO gtmsmanager;

--
-- Name: COLUMN tab_city_bak0905.level; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_city_bak0905.level IS '层级';


--
-- Name: tab_city_bak0926; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_city_bak0926 (
    city_id character varying(20) NOT NULL,
    parent_id character varying(20),
    city_name character varying(50) NOT NULL,
    staff_id character varying(30),
    remark character varying(100),
    sequ numeric(5,0) DEFAULT 0 NOT NULL,
    level smallint
);


ALTER TABLE public.tab_city_bak0926 OWNER TO gtmsmanager;

--
-- Name: COLUMN tab_city_bak0926.level; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_city_bak0926.level IS '层级';


--
-- Name: tab_city_bak092601; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_city_bak092601 (
    city_id character varying(20) NOT NULL,
    parent_id character varying(20),
    city_name character varying(50) NOT NULL,
    staff_id character varying(30),
    remark character varying(100),
    sequ numeric(5,0) DEFAULT 0 NOT NULL,
    level smallint
);


ALTER TABLE public.tab_city_bak092601 OWNER TO gtmsmanager;

--
-- Name: COLUMN tab_city_bak092601.level; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_city_bak092601.level IS '层级';


--
-- Name: tab_city_code; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_city_code (
    city_id character varying(20) NOT NULL,
    province_code character varying(20),
    province_name character varying(20),
    city_code character varying(20),
    city_name character varying(20),
    area_code character varying(20),
    area_name character varying(20),
    levels numeric(1,0)
);


ALTER TABLE public.tab_city_code OWNER TO gtmsmanager;

--
-- Name: tab_cmd; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_cmd (
    rpc_id numeric(10,0) NOT NULL,
    rpc_name character varying(100) NOT NULL,
    rpc_desc character varying(200)
);


ALTER TABLE public.tab_cmd OWNER TO gtmsmanager;

--
-- Name: tab_conf_node; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_conf_node (
    node_id numeric(4,0) NOT NULL,
    conf_type_id numeric(4,0) NOT NULL,
    node_path text NOT NULL,
    node_name character varying(100) NOT NULL,
    node_value_type numeric(1,0) NOT NULL,
    pre_ijk numeric(1,0) NOT NULL,
    input_type numeric(1,0) NOT NULL,
    type_check character varying(100),
    remark character varying(100)
);


ALTER TABLE public.tab_conf_node OWNER TO gtmsmanager;

--
-- Name: tab_cpe_classify_statistic; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_cpe_classify_statistic (
    id integer NOT NULL,
    city_id integer,
    city_name character varying(255),
    vendor_id integer,
    vendor_name character varying(255),
    online_status smallint,
    update_time character varying(32),
    total integer
);


ALTER TABLE public.tab_cpe_classify_statistic OWNER TO gtmsmanager;

--
-- Name: tab_cpe_classify_statistic_id_seq; Type: SEQUENCE; Schema: public; Owner: gtmsmanager
--

CREATE SEQUENCE public.tab_cpe_classify_statistic_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.tab_cpe_classify_statistic_id_seq OWNER TO gtmsmanager;

--
-- Name: tab_cpe_classify_statistic_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: gtmsmanager
--

ALTER SEQUENCE public.tab_cpe_classify_statistic_id_seq OWNED BY public.tab_cpe_classify_statistic.id;


--
-- Name: tab_cpe_faultcode; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_cpe_faultcode (
    fault_code numeric(6,0) NOT NULL,
    fault_type numeric(1,0) NOT NULL,
    fault_name character varying(100) NOT NULL,
    fault_desc character varying(100),
    fault_reason character varying(100),
    solutions character varying(100)
);


ALTER TABLE public.tab_cpe_faultcode OWNER TO gtmsmanager;

--
-- Name: COLUMN tab_cpe_faultcode.fault_type; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_cpe_faultcode.fault_type IS '0:success
1:system fault
2:server fault
3:client fault
4:other fault
';


--
-- Name: tab_customer_ftth; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_customer_ftth (
    user_id numeric(10,0) NOT NULL,
    loid character varying(40) NOT NULL,
    gw_type numeric(1,0) NOT NULL,
    dealdate numeric(14,0),
    test_stat numeric(2,0) NOT NULL,
    last_modified numeric(10,0) NOT NULL
);


ALTER TABLE public.tab_customer_ftth OWNER TO gtmsmanager;

--
-- Name: COLUMN tab_customer_ftth.test_stat; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_customer_ftth.test_stat IS '测试状态 1：未测试 default 2：已测试';


--
-- Name: tab_customerinfo; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_customerinfo (
    customer_id bigint NOT NULL,
    customer_name character varying(100) NOT NULL,
    customer_pwd character varying(255),
    customer_type character varying(10) DEFAULT '-1'::character varying,
    customer_size character varying(10) DEFAULT '-1'::character varying,
    customer_address character varying(255) DEFAULT '-1'::character varying,
    linkman character varying(255),
    linkphone character varying(255),
    email character varying(100),
    mobile character varying(20),
    customer_state smallint,
    update_time bigint,
    opendate bigint,
    pausedate bigint,
    closedate bigint,
    city_id character varying(20) DEFAULT '00'::character varying,
    office_id character varying(20) DEFAULT '0'::character varying,
    zone_id character varying(20) DEFAULT '0'::character varying,
    customer_account character varying(100)
);


ALTER TABLE public.tab_customerinfo OWNER TO gtmsmanager;

--
-- Name: tab_dev_batch_restart; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_dev_batch_restart (
    task_id character varying(20) NOT NULL,
    device_id character varying(10) NOT NULL,
    add_time numeric(10,0) NOT NULL,
    restart_status numeric(2,0) NOT NULL,
    restart_time numeric(10,0)
);


ALTER TABLE public.tab_dev_batch_restart OWNER TO gtmsmanager;

--
-- Name: tab_dev_black; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_dev_black (
    device_id character varying(64) NOT NULL,
    device_serialnumber character varying(100) NOT NULL,
    add_time integer NOT NULL
);


ALTER TABLE public.tab_dev_black OWNER TO gtmsmanager;

--
-- Name: tab_dev_group; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_dev_group (
    group_id integer NOT NULL,
    group_name character varying(64) NOT NULL,
    group_type integer DEFAULT 0 NOT NULL,
    group_count integer DEFAULT 0 NOT NULL,
    add_time integer NOT NULL,
    update_time integer NOT NULL,
    group_conditions character varying(500),
    file_name character varying(64),
    file_path character varying(200),
    user_id character varying(24)
);


ALTER TABLE public.tab_dev_group OWNER TO gtmsmanager;

--
-- Name: tab_dev_group_group_id_seq; Type: SEQUENCE; Schema: public; Owner: gtmsmanager
--

ALTER TABLE public.tab_dev_group ALTER COLUMN group_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.tab_dev_group_group_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: tab_dev_group_import; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_dev_group_import (
    group_id integer NOT NULL,
    device_id character varying(64) NOT NULL,
    device_serialnumber character varying(100) NOT NULL,
    city_id character varying(100),
    add_time integer NOT NULL
);


ALTER TABLE public.tab_dev_group_import OWNER TO gtmsmanager;

--
-- Name: tab_dev_recovery_record; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_dev_recovery_record (
    user_id numeric(10,0) NOT NULL,
    loid character varying(40) NOT NULL,
    device_id character varying(40) NOT NULL,
    city_id character varying(20) NOT NULL,
    device_serialnumber character varying(40) NOT NULL,
    status character varying(2),
    quantity numeric(2,0),
    is_completed numeric(1,0),
    recovery_time numeric(10,0),
    cancellation_time numeric(10,0)
);


ALTER TABLE public.tab_dev_recovery_record OWNER TO gtmsmanager;

--
-- Name: COLUMN tab_dev_recovery_record.status; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_dev_recovery_record.status IS '0������������������������������������1����������������';


--
-- Name: COLUMN tab_dev_recovery_record.quantity; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_dev_recovery_record.quantity IS '0��������������������1������������1����2������������2��';


--
-- Name: COLUMN tab_dev_recovery_record.recovery_time; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_dev_recovery_record.recovery_time IS '��������������������������';


--
-- Name: COLUMN tab_dev_recovery_record.cancellation_time; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_dev_recovery_record.cancellation_time IS '��������';


--
-- Name: tab_dev_stack_info; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_dev_stack_info (
    device_id character varying(20) NOT NULL,
    gather_time numeric(10,0) NOT NULL,
    wan_type numeric(2,0) NOT NULL,
    ip_type numeric(2,0) NOT NULL,
    ipv6_ipaddressorigin character varying(100),
    ipv6_prefixorigin character varying(100),
    ipv6_prefixdelegation_enabled character varying(100),
    serv_type_id numeric(4,0) NOT NULL
);


ALTER TABLE public.tab_dev_stack_info OWNER TO gtmsmanager;

--
-- Name: tab_device_bandwidth_rule; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_device_bandwidth_rule (
    id bigint NOT NULL,
    vendor_id integer,
    model_id integer,
    bandwidth_node_val character varying(255),
    bandwidth_real_val character varying(255),
    is_default integer,
    is_5g integer,
    band_width_node character(200)
);


ALTER TABLE public.tab_device_bandwidth_rule OWNER TO gtmsmanager;

--
-- Name: COLUMN tab_device_bandwidth_rule.id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_device_bandwidth_rule.id IS 'id';


--
-- Name: tab_device_bandwidth_rule_bak; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_device_bandwidth_rule_bak (
    id bigint,
    vendor_id integer,
    model_id integer,
    bandwidth_node_val character varying(255),
    bandwidth_real_val character varying(255),
    is_default integer,
    is_5g integer,
    band_width_node character(200)
);


ALTER TABLE public.tab_device_bandwidth_rule_bak OWNER TO gtmsmanager;

--
-- Name: tab_device_bindwidth_rule_id_seq; Type: SEQUENCE; Schema: public; Owner: gtmsmanager
--

ALTER TABLE public.tab_device_bandwidth_rule ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.tab_device_bindwidth_rule_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: tab_device_model_attribute; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_device_model_attribute (
    vendor_id character varying(6) NOT NULL,
    device_model_id character varying(6) NOT NULL,
    device_model character varying(64),
    rate numeric(10,0) NOT NULL
);


ALTER TABLE public.tab_device_model_attribute OWNER TO gtmsmanager;

--
-- Name: tab_device_model_scrap; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_device_model_scrap (
    device_id character varying(10) NOT NULL,
    loid character varying(40),
    username character varying(40),
    status numeric(2,0) NOT NULL
);


ALTER TABLE public.tab_device_model_scrap OWNER TO gtmsmanager;

--
-- Name: tab_device_ty_version; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_device_ty_version (
    devicetype_id numeric(10,0),
    vendor_name character varying(64),
    device_model character varying(64),
    hardwareversion character varying(30),
    softwareversion character varying(100)
);


ALTER TABLE public.tab_device_ty_version OWNER TO gtmsmanager;

--
-- Name: tab_device_version_attribute; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_device_version_attribute (
    devicetype_id numeric(4,0) NOT NULL,
    is_support200 numeric(1,0) DEFAULT 0 NOT NULL,
    is_speedtest numeric(1,0) DEFAULT 0 NOT NULL,
    is_tygate numeric(1,0) NOT NULL,
    gbbroadband numeric(2,0),
    device_version_type numeric(10,0),
    wifi character varying(10),
    wifi_frequency numeric(20,0),
    download_max_wifi numeric(10,0),
    gigabit_port numeric(10,0),
    gigabit_port_type numeric(10,0),
    download_max_lan numeric(10,0),
    power character varying(20),
    terminal_access_time character varying(20),
    is_security_plugin numeric(1,0),
    security_plugin_type numeric(1,0),
    is_probe numeric(1,0),
    iscloudnet numeric(1,0),
    wifi_ability numeric(1,0)
);


ALTER TABLE public.tab_device_version_attribute OWNER TO gtmsmanager;

--
-- Name: COLUMN tab_device_version_attribute.is_support200; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_device_version_attribute.is_support200 IS '0:������
1������';


--
-- Name: COLUMN tab_device_version_attribute.is_speedtest; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_device_version_attribute.is_speedtest IS '1:是 0:否';


--
-- Name: COLUMN tab_device_version_attribute.is_tygate; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_device_version_attribute.is_tygate IS '1：是天翼网关
0：不是天翼网关
';


--
-- Name: COLUMN tab_device_version_attribute.iscloudnet; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_device_version_attribute.iscloudnet IS '1支持 0不支持';


--
-- Name: COLUMN tab_device_version_attribute.wifi_ability; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_device_version_attribute.wifi_ability IS '0:无 1:802.11b 2:802.11b/g 3:802.11b/g/n 4:802.11b/g/n/ac';


--
-- Name: tab_devicefault; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_devicefault (
    username character varying(40) NOT NULL,
    device_id character varying(10) NOT NULL,
    fault_id character varying(10),
    faulttime numeric(10,0) NOT NULL,
    dealstaff character varying(80),
    dealstaffid character varying(10)
);


ALTER TABLE public.tab_devicefault OWNER TO gtmsmanager;

--
-- Name: COLUMN tab_devicefault.fault_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_devicefault.fault_id IS '故障原因：
1．用户不能上网
2．设备部分端口损坏
3．设备外观有缺陷
4．管理通道不通，用户可以上网
5．其他原因
';


--
-- Name: tab_devicemodel_template; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_devicemodel_template (
    device_model_id character varying(4) NOT NULL,
    net_bridge_templateid integer,
    net_route_templateid integer,
    net_route_ipv4_templateid integer,
    net_allroute_templateid integer,
    net_dhcp_templateid integer DEFAULT '-1'::integer,
    iptv_bridge_templateid integer,
    iptv_allroute_templateid integer,
    iptv_dhcp_templateid integer DEFAULT '-1'::integer,
    iptv_route_templateid integer,
    voip_sip_templateid integer,
    voip_h248_templateid integer,
    voip_ims_templateid integer,
    voip_sip_dhcp_templateid integer,
    voip_sip_bridge_templateid integer,
    voip_sip_static_templateid integer,
    hqos_open_templateid integer,
    hqos_chan_templateid integer,
    hqos_close_templateid integer,
    vpn_bridge_templateid integer,
    vpn_route_templateid integer,
    net_static_templateid integer,
    vpn_static_templateid integer
);


ALTER TABLE public.tab_devicemodel_template OWNER TO gtmsmanager;

--
-- Name: tab_devicetype_info; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_devicetype_info (
    devicetype_id character varying(30) NOT NULL,
    vendor_id character varying(6) NOT NULL,
    device_model_id character varying(4) NOT NULL,
    specversion character varying(30),
    hardwareversion character varying(30),
    softwareversion character varying(100) NOT NULL,
    area_id bigint,
    prot_id character varying(30) DEFAULT 1 NOT NULL,
    add_time character varying(30),
    is_check character varying(30) DEFAULT '-1'::integer,
    rela_dev_type_id character varying(30) DEFAULT 2,
    access_style_relay_id smallint,
    is_ftth character varying(30) DEFAULT 0,
    ip_type character varying(30) DEFAULT 1 NOT NULL,
    is_normal character varying(30) DEFAULT 0 NOT NULL,
    spec_id character varying(30) DEFAULT 1 NOT NULL,
    ip_model_type character varying(30) DEFAULT 1 NOT NULL,
    zeroconf smallint,
    versionttime character varying(30),
    mbbroadband character varying(30),
    is_awifi character varying(30) DEFAULT 1,
    is_ott smallint,
    is_recent_version smallint DEFAULT 0,
    is_multicast character varying(30) DEFAULT 1,
    is_qoe smallint DEFAULT 0,
    is_highversion integer DEFAULT 0,
    dm_type character varying(10)
);


ALTER TABLE public.tab_devicetype_info OWNER TO gtmsmanager;

--
-- Name: tab_devicetype_info_port; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_devicetype_info_port (
    devicetype_id numeric(4,0) NOT NULL,
    port_name character varying(20) NOT NULL,
    port_dir character varying(100) NOT NULL,
    port_type numeric(10,0) NOT NULL,
    port_desc character varying(100),
    add_time numeric(10,0),
    acc_oid numeric(10,0)
);


ALTER TABLE public.tab_devicetype_info_port OWNER TO gtmsmanager;

--
-- Name: COLUMN tab_devicetype_info_port.port_type; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_devicetype_info_port.port_type IS '������1
wlan��2
lan��3';


--
-- Name: tab_devicetype_info_servertype; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_devicetype_info_servertype (
    devicetype_id numeric(4,0) NOT NULL,
    server_type numeric(2,0) NOT NULL,
    "time" numeric(10,0),
    acc_oid numeric(10,0)
);


ALTER TABLE public.tab_devicetype_info_servertype OWNER TO gtmsmanager;

--
-- Name: COLUMN tab_devicetype_info_servertype.server_type; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_devicetype_info_servertype.server_type IS '0��IMS SIP
1��������SIP
2��H248
';


--
-- Name: tab_devicetype_lan_attr; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_devicetype_lan_attr (
    devicetype_id numeric(4,0) NOT NULL,
    lan_name character varying(32) NOT NULL,
    lan_value character varying(32) NOT NULL
);


ALTER TABLE public.tab_devicetype_lan_attr OWNER TO gtmsmanager;

--
-- Name: tab_devicetypetask_info; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_devicetypetask_info (
    vendor character varying(64) NOT NULL,
    device_model character varying(64) NOT NULL,
    hardwareversion character varying(30) NOT NULL,
    softwareversion character varying(30) NOT NULL,
    rela_dev_type_id numeric(2,0) NOT NULL,
    access_style_relay_id numeric(2,0) NOT NULL,
    spec character varying(25) NOT NULL,
    reason text NOT NULL,
    "time" numeric(15,0) NOT NULL,
    is_speedtest numeric(2,0)
);


ALTER TABLE public.tab_devicetypetask_info OWNER TO gtmsmanager;

--
-- Name: tab_diagnosis_iad; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_diagnosis_iad (
    device_id character varying(10) NOT NULL,
    iaddiagnosticsstate character varying(20),
    testserver numeric(1,0),
    registresult numeric(1,0),
    reason character varying(50),
    gather_time numeric(10,0)
);


ALTER TABLE public.tab_diagnosis_iad OWNER TO gtmsmanager;

--
-- Name: tab_diagnosis_poninfo; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_diagnosis_poninfo (
    device_id character varying(10) NOT NULL,
    status character varying(30),
    tx_power character varying(20),
    rx_power character varying(20),
    transceiver_temperature character varying(20),
    supply_vottage character varying(20),
    bias_current character varying(20),
    bytes_sent character varying(20),
    bytes_received character varying(20),
    packets_sent character varying(20),
    packets_received character varying(20),
    sunicast_packets character varying(20),
    runicast_packets character varying(20),
    smulticast_packets character varying(20),
    rmulticast_packets character varying(20),
    sbroadcast_packets character varying(20),
    rbroadcast_packets character varying(20),
    fec_error character varying(20),
    hec_error character varying(20),
    drop_packets character varying(20),
    spause_packets character varying(20),
    rpause_packets character varying(20),
    gather_time numeric(10,0)
);


ALTER TABLE public.tab_diagnosis_poninfo OWNER TO gtmsmanager;

--
-- Name: tab_diagnosis_voipline; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_diagnosis_voipline (
    device_id character varying(10) NOT NULL,
    linenum numeric(2,0),
    status character varying(20),
    gather_time numeric(10,0)
);


ALTER TABLE public.tab_diagnosis_voipline OWNER TO gtmsmanager;

--
-- Name: tab_diagnosis_wan_conn; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_diagnosis_wan_conn (
    device_id character varying(10) NOT NULL,
    connecttype character varying(20),
    connectstatus character varying(20),
    ipaddress character varying(50),
    dnsserver character varying(50),
    subnetmask character varying(50),
    defaultgateway character varying(50),
    serv_list character varying(20),
    gather_time numeric(10,0)
);


ALTER TABLE public.tab_diagnosis_wan_conn OWNER TO gtmsmanager;

--
-- Name: tab_digit_map; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_digit_map (
    digit_map_code character varying(10) NOT NULL,
    digit_map_value text NOT NULL,
    remark character varying(100)
);


ALTER TABLE public.tab_digit_map OWNER TO gtmsmanager;

--
-- Name: tab_egw_bsn_open_original; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_egw_bsn_open_original (
    id character varying(30) NOT NULL,
    bnet_id character varying(16),
    bnet_account character varying(32),
    product_spec_id character varying(16),
    customer_name character varying(96),
    type numeric(2,0),
    result numeric(1,0),
    result_info character varying(128),
    receive_date numeric(16,0),
    status numeric(1,0),
    wp_flag numeric(1,0),
    result_spec numeric(1,0),
    result_spec_desc character varying(200),
    oui character varying(6),
    device_type character varying(50),
    device_serialnumber character varying(64),
    "time" numeric(10,0),
    city_id character varying(20),
    order_type numeric(6,0),
    username character varying(50),
    passwd character varying(50),
    dev_sheet_id character varying(20),
    sheet_para_desc text
);


ALTER TABLE public.tab_egw_bsn_open_original OWNER TO gtmsmanager;

--
-- Name: COLUMN tab_egw_bsn_open_original.result; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_egw_bsn_open_original.result IS '具体见接口表
0：成功
1: 失败
广东：
0： 成功
－1：订购失败
－2：参数错误
－3：hashCode错误
';


--
-- Name: COLUMN tab_egw_bsn_open_original.status; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_egw_bsn_open_original.status IS '0:等待执行
1：已经执行（指发送给WorkPro）
';


--
-- Name: COLUMN tab_egw_bsn_open_original.wp_flag; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_egw_bsn_open_original.wp_flag IS '0：workpro不执行
1：workpro执行
2：TR069
';


--
-- Name: COLUMN tab_egw_bsn_open_original.result_spec; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_egw_bsn_open_original.result_spec IS '0：成功
1：用户重复
2：根域为空
3：找不到对应的根域
4：域名己注册
5：插入数据库失败
6：DNS服务器注册该域名失败
其它直接填数字
';


--
-- Name: COLUMN tab_egw_bsn_open_original.device_type; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_egw_bsn_open_original.device_type IS 'HGW:
e8-a,
e8-b,
e8-c
EGW:
Navigator1-1
Navigator1-2
Navigator2-1
Navigator2-2
';


--
-- Name: COLUMN tab_egw_bsn_open_original.order_type; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_egw_bsn_open_original.order_type IS '1: ADSL
2: 普通LAN
3: 普通光纤
4: 专线LAN
5: 专线光纤
';


--
-- Name: tab_egw_net_serv_param; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_egw_net_serv_param (
    user_id numeric(10,0) NOT NULL,
    username character varying(40) NOT NULL,
    ip_type numeric(2,0) NOT NULL,
    dslite_enable numeric(2,0) NOT NULL,
    aftr_mode numeric(2,0),
    aftr_ip character varying(40),
    ipv6_address_origin character varying(20),
    ipv6_address character varying(40),
    ipv6_dns character varying(40),
    ipv6_prefix_origin character varying(20),
    ipv6_prefix character varying(40),
    max_net_num numeric(2,0),
    dpi numeric(1,0),
    serv_type_id numeric(4,0)
);


ALTER TABLE public.tab_egw_net_serv_param OWNER TO gtmsmanager;

--
-- Name: COLUMN tab_egw_net_serv_param.ip_type; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_egw_net_serv_param.ip_type IS '1：ipv4 2：ipv6 3：ipv4+ipv6';


--
-- Name: COLUMN tab_egw_net_serv_param.dslite_enable; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_egw_net_serv_param.dslite_enable IS '0：否   1：是
';


--
-- Name: COLUMN tab_egw_net_serv_param.aftr_mode; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_egw_net_serv_param.aftr_mode IS ' 0，自动获取  1，手工设置';


--
-- Name: COLUMN tab_egw_net_serv_param.ipv6_address_origin; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_egw_net_serv_param.ipv6_address_origin IS 'AutoConfigured
DHCPv6
 Static
None';


--
-- Name: COLUMN tab_egw_net_serv_param.ipv6_prefix_origin; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_egw_net_serv_param.ipv6_prefix_origin IS 'PrefixDelegation
RouterAdvertisement
Static
None';


--
-- Name: COLUMN tab_egw_net_serv_param.dpi; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_egw_net_serv_param.dpi IS '0：关闭 1：开启';


--
-- Name: tab_egw_voip_serv_param; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_egw_voip_serv_param (
    user_id numeric(10,0) NOT NULL,
    line_id numeric(3,0) NOT NULL,
    voip_username character varying(30),
    voip_passwd character varying(100),
    sip_id numeric(5,0),
    updatetime numeric(10,0) NOT NULL,
    voip_phone character varying(13),
    parm_stat numeric(1,0),
    protocol numeric(1,0),
    voip_port character varying(20),
    reg_id character varying(30),
    reg_id_type numeric(1,0),
    uri character varying(50),
    user_agent_domain character varying(50),
    digit_map character varying(10)
);


ALTER TABLE public.tab_egw_voip_serv_param OWNER TO gtmsmanager;

--
-- Name: COLUMN tab_egw_voip_serv_param.parm_stat; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_egw_voip_serv_param.parm_stat IS '1:成功
-1:失败
0:未做,默认';


--
-- Name: COLUMN tab_egw_voip_serv_param.protocol; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_egw_voip_serv_param.protocol IS 'SIP：1
H.248：2
字段为空默认为SIP';


--
-- Name: COLUMN tab_egw_voip_serv_param.reg_id_type; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_egw_voip_serv_param.reg_id_type IS '0：IP地址，
1：域名，
2：设备名
新疆实施要求为域名';


--
-- Name: tab_egwcustomer; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_egwcustomer (
    user_id numeric(10,0) NOT NULL,
    gather_id character varying(30),
    username character varying(40) NOT NULL,
    passwd character varying(20),
    city_id character varying(20),
    cotno character varying(16),
    bill_type_id numeric(6,0),
    next_bill_type_id numeric(6,0),
    cust_type_id numeric(6,0),
    user_type_id numeric(2,0),
    bindtype numeric(65,30),
    virtualnum numeric(10,0),
    numcharacter character varying(10),
    access_style_id numeric(6,0),
    aut_flag character varying(1),
    service_set character varying(255),
    realname character varying(50),
    sex character varying(2),
    cred_type_id numeric(6,0),
    credno character varying(50),
    address character varying(100),
    office_id character varying(20),
    zone_id character varying(20),
    access_kind_id numeric(6,0),
    trade_id numeric(6,0),
    licenceregno character varying(50),
    occupation_id numeric(6,0),
    education_id numeric(6,0),
    vipcardno character varying(30),
    contractno character varying(50),
    linkman character varying(100),
    linkman_credno character varying(20),
    linkphone character varying(50),
    linkaddress text,
    mobile character varying(15),
    email character varying(100),
    agent character varying(20),
    agent_credno character varying(20),
    agentphone character varying(20),
    adsl_res numeric(6,0),
    adsl_card character varying(30),
    adsl_dev character varying(30),
    adsl_ser character varying(30),
    isrepair character varying(1),
    bandwidth numeric(10,0),
    ipaddress character varying(15),
    overipnum numeric(6,0),
    ipmask character varying(15),
    gateway character varying(15),
    macaddress character varying(20),
    device_id character varying(100),
    device_ip character varying(15),
    device_shelf numeric(10,0),
    device_frame numeric(10,0),
    device_slot numeric(10,0),
    device_port numeric(10,0),
    basdevice_id character varying(40),
    basdevice_ip character varying(15),
    basdevice_shelf numeric(4,0),
    basdevice_frame numeric(4,0),
    basdevice_slot numeric(6,0),
    basdevice_port numeric(6,0),
    vlanid character varying(20),
    workid character varying(20),
    user_state character varying(1) DEFAULT '1'::character varying NOT NULL,
    opendate numeric(10,0),
    onlinedate numeric(10,0),
    pausedate numeric(10,0),
    closedate numeric(10,0),
    updatetime numeric(10,0),
    staff_id character varying(30),
    remark character varying(100),
    phonenumber character varying(15),
    cableid character varying(10),
    bwlevel numeric(4,3),
    vpiid character varying(10),
    vciid numeric(6,0),
    adsl_hl numeric(2,1),
    userline numeric(6,0),
    dslamserialno character varying(30),
    movedate numeric(10,0),
    dealdate numeric(14,0),
    opmode character varying(6),
    maxattdnrate numeric(10,0),
    upwidth numeric(10,0),
    oui character varying(6),
    device_serialnumber character varying(64),
    serv_type_id numeric(4,0) DEFAULT 10 NOT NULL,
    max_user_number numeric(4,0),
    wan_value_1 character varying(200) DEFAULT '-1'::character varying NOT NULL,
    wan_value_2 character varying(200) DEFAULT '-1'::character varying NOT NULL,
    open_status numeric(1,0),
    customer_id character varying(40),
    wan_type numeric(2,0) DEFAULT 1 NOT NULL,
    lan_num numeric(10,0),
    ssid_num numeric(10,0),
    work_model numeric(1,0),
    bind_port character varying(200),
    flag_pvc numeric(1,0) DEFAULT 0 NOT NULL,
    binddate numeric(10,0),
    stat_bind_enab numeric(1,0) DEFAULT 0 NOT NULL,
    bind_flag numeric(15,0),
    is_chk_bind numeric(1,0),
    spec_id numeric(2,0),
    longitude character varying(20),
    latitude character varying(20)
);


ALTER TABLE public.tab_egwcustomer OWNER TO gtmsmanager;

--
-- Name: COLUMN tab_egwcustomer.cust_type_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_egwcustomer.cust_type_id IS '0����������
1����������
2����������
';


--
-- Name: COLUMN tab_egwcustomer.user_type_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_egwcustomer.user_type_id IS 'user_type(user_type_id)  ';


--
-- Name: COLUMN tab_egwcustomer.access_style_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_egwcustomer.access_style_id IS 'gw_order_type
1,ADSL
2,LAN
3,����ADSL
4,����LAN
5,����ADSL
6,����LAN';


--
-- Name: COLUMN tab_egwcustomer.user_state; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_egwcustomer.user_state IS '1:����
2:����
';


--
-- Name: COLUMN tab_egwcustomer.adsl_hl; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_egwcustomer.adsl_hl IS 'gw_access_type
1,ADSL
2,LAN
3,����';


--
-- Name: COLUMN tab_egwcustomer.userline; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_egwcustomer.userline IS 'bind_type(bind_type_id)
0:IPOSS
1:��������
2:��������
3:��������';


--
-- Name: COLUMN tab_egwcustomer.opmode; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_egwcustomer.opmode IS '��������
0������
1����';


--
-- Name: COLUMN tab_egwcustomer.serv_type_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_egwcustomer.serv_type_id IS 'user_type(user_type_id)      varchar(20)
1����������
2��BSS����
3����������
4��BSS����';


--
-- Name: COLUMN tab_egwcustomer.open_status; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_egwcustomer.open_status IS '1:����
0������
-1:����
';


--
-- Name: COLUMN tab_egwcustomer.wan_type; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_egwcustomer.wan_type IS '1 ����
2 ����
2 ����IP
3 DHCP
';


--
-- Name: COLUMN tab_egwcustomer.work_model; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_egwcustomer.work_model IS '1����
2����
3����������
';


--
-- Name: COLUMN tab_egwcustomer.flag_pvc; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_egwcustomer.flag_pvc IS '1:��PVC
0:��������
';


--
-- Name: COLUMN tab_egwcustomer.stat_bind_enab; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_egwcustomer.stat_bind_enab IS '1:����
0:������
';


--
-- Name: COLUMN tab_egwcustomer.bind_flag; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_egwcustomer.bind_flag IS '0:����
Other:bind_log(bind_id)
';


--
-- Name: COLUMN tab_egwcustomer.is_chk_bind; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_egwcustomer.is_chk_bind IS '0:��������1������2����';


--
-- Name: COLUMN tab_egwcustomer.spec_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_egwcustomer.spec_id IS 'tab_bss_dev_port������id����';


--
-- Name: tab_egwcustomer_bak; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_egwcustomer_bak (
    user_id numeric(10,0) NOT NULL,
    gather_id character varying(30),
    username character varying(40) NOT NULL,
    passwd character varying(20),
    city_id character varying(20),
    cotno character varying(16),
    bill_type_id numeric(6,0),
    next_bill_type_id numeric(6,0),
    cust_type_id numeric(6,0),
    user_type_id numeric(2,0),
    bindtype numeric(65,30),
    virtualnum numeric(10,0),
    numcharacter character varying(10),
    access_style_id numeric(6,0),
    aut_flag character varying(1),
    service_set character varying(255),
    realname character varying(50),
    sex character varying(2),
    cred_type_id numeric(6,0),
    credno character varying(50),
    address character varying(100),
    office_id character varying(20),
    zone_id character varying(20),
    access_kind_id numeric(6,0),
    trade_id numeric(6,0),
    licenceregno character varying(50),
    occupation_id numeric(6,0),
    education_id numeric(6,0),
    vipcardno character varying(30),
    contractno character varying(50),
    linkman character varying(100),
    linkman_credno character varying(20),
    linkphone character varying(50),
    linkaddress text,
    mobile character varying(15),
    email character varying(100),
    agent character varying(20),
    agent_credno character varying(20),
    agentphone character varying(20),
    adsl_res numeric(6,0),
    adsl_card character varying(30),
    adsl_dev character varying(30),
    adsl_ser character varying(30),
    isrepair character varying(1),
    bandwidth numeric(10,0),
    ipaddress character varying(15),
    overipnum numeric(6,0),
    ipmask character varying(15),
    gateway character varying(15),
    macaddress character varying(20),
    device_id character varying(100),
    device_ip character varying(15),
    device_shelf numeric(10,0),
    device_frame numeric(10,0),
    device_slot numeric(10,0),
    device_port numeric(10,0),
    basdevice_id character varying(40),
    basdevice_ip character varying(15),
    basdevice_shelf numeric(4,0),
    basdevice_frame numeric(4,0),
    basdevice_slot numeric(6,0),
    basdevice_port numeric(6,0),
    vlanid character varying(20),
    workid character varying(20),
    user_state character varying(1) NOT NULL,
    opendate numeric(10,0),
    onlinedate numeric(10,0),
    pausedate numeric(10,0),
    closedate numeric(10,0),
    updatetime numeric(10,0),
    staff_id character varying(30),
    remark character varying(100),
    phonenumber character varying(15),
    cableid character varying(10),
    bwlevel numeric(4,3),
    vpiid character varying(10),
    vciid numeric(6,0),
    adsl_hl numeric(2,1),
    userline numeric(6,0),
    dslamserialno character varying(30),
    movedate numeric(10,0),
    dealdate numeric(14,0),
    opmode character varying(6),
    maxattdnrate numeric(10,0),
    upwidth numeric(10,0),
    oui character varying(6),
    device_serialnumber character varying(64),
    serv_type_id numeric(4,0) NOT NULL,
    max_user_number numeric(4,0),
    wan_value_1 character varying(200) NOT NULL,
    wan_value_2 character varying(200) NOT NULL,
    open_status numeric(1,0),
    wan_type numeric(2,0) NOT NULL,
    binddate numeric(10,0),
    stat_bind_enab numeric(1,0) NOT NULL,
    bind_flag numeric(15,0),
    is_chk_bind numeric(1,0),
    customer_id character varying(30) NOT NULL,
    spec_id numeric(2,0),
    network_spec character varying(10)
);


ALTER TABLE public.tab_egwcustomer_bak OWNER TO gtmsmanager;

--
-- Name: tab_excel_syn_accounts; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_excel_syn_accounts (
    enname character varying(20) NOT NULL,
    chname character varying(40),
    city_id character varying(20) NOT NULL,
    dept_name character varying(40) NOT NULL,
    dept_full_name character varying(80),
    email character varying(40),
    mobilephone character varying(15),
    telephone character varying(20),
    employee_type character varying(20),
    dept_id character varying(30),
    synchronize_time numeric(16,0) NOT NULL,
    itms_account character varying(80) NOT NULL,
    data_from character varying(80) NOT NULL
);


ALTER TABLE public.tab_excel_syn_accounts OWNER TO gtmsmanager;

--
-- Name: tab_file_server; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_file_server (
    dir_id bigint NOT NULL,
    gather_id character varying(30) NOT NULL,
    server_name character varying(100),
    inner_url character varying(200) NOT NULL,
    outter_url character varying(200) NOT NULL,
    server_dir character varying(80) NOT NULL,
    access_user character varying(30),
    access_passwd character varying(30),
    file_type numeric(1,0) NOT NULL
);


ALTER TABLE public.tab_file_server OWNER TO gtmsmanager;

--
-- Name: COLUMN tab_file_server.file_type; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_file_server.file_type IS '1-版本文件；2-配置文件；3-日志文件；4-web日志文件';


--
-- Name: tab_fttr_master_slave; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_fttr_master_slave (
    master_device_id character varying(10) NOT NULL,
    bind_time integer,
    slave_device_number character varying(100),
    slave_device_status integer,
    slave_loid character varying(100)
);


ALTER TABLE public.tab_fttr_master_slave OWNER TO gtmsmanager;

--
-- Name: tab_gather_interface; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_gather_interface (
    device_id character varying(10) NOT NULL,
    interfacename character varying(50) NOT NULL,
    resp_result text,
    updatetime numeric(10,0),
    rstcode character varying(6)
);


ALTER TABLE public.tab_gather_interface OWNER TO gtmsmanager;

--
-- Name: tab_group; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_group (
    group_oid numeric(10,0) NOT NULL,
    group_poid numeric(10,0),
    group_rootid numeric(10,0),
    group_name character varying(50),
    group_desc character varying(80)
);


ALTER TABLE public.tab_group OWNER TO gtmsmanager;

--
-- Name: tab_gw_card; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_gw_card (
    card_id character varying(10) NOT NULL,
    card_serialnumber character varying(9) NOT NULL,
    author_code character varying(16) NOT NULL,
    user_id numeric(10,0) NOT NULL,
    online_status numeric(1,0) NOT NULL
);


ALTER TABLE public.tab_gw_card OWNER TO gtmsmanager;

--
-- Name: tab_gw_device; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_gw_device (
    device_id integer NOT NULL,
    device_group character varying(25),
    oui character varying(6) NOT NULL,
    device_serialnumber character varying(64) NOT NULL,
    device_name character varying(80),
    manage_staff character varying(30),
    city_id character varying(20) NOT NULL,
    office_id character varying(20),
    zone_id character varying(20),
    device_addr character varying(50),
    complete_time numeric(10,0),
    buy_time numeric(14,0),
    service_year numeric(3,0),
    staff_id character varying(30),
    remark character varying(100),
    loopback_ip character varying(100),
    pdevice_id character varying(30),
    interface_id numeric(10,0),
    device_status numeric(1,0) NOT NULL,
    device_id_ex character varying(255),
    res_pro_id character varying(50),
    gather_id character varying(30) NOT NULL,
    oper_status numeric(1,0),
    devicetype_id character varying(30) NOT NULL,
    maxenvelopes numeric(4,0),
    retrycount numeric(10,0),
    cr_port numeric(10,0),
    cr_path character varying(50),
    cpe_mac character varying(30),
    cpe_currentupdatetime numeric(10,0),
    cpe_allocatedstatus numeric(1,0) NOT NULL,
    cpe_currentstatus numeric(1,0),
    cpe_operationinfo character varying(255),
    cpe_username character varying(50),
    cpe_passwd character varying(50),
    acs_username character varying(50),
    acs_passwd character varying(50),
    device_type character varying(50),
    x_com_username character varying(50) NOT NULL,
    x_com_passwd character varying(50) NOT NULL,
    gw_type numeric(1,0),
    device_model_id character varying(4) NOT NULL,
    snmp_udp numeric(5,0),
    customer_id character varying(10),
    device_url character varying(200),
    resource_type_id numeric(6,0),
    os_version character varying(50),
    x_com_passwd_old character varying(50) DEFAULT 'nE7jA%5m'::character varying NOT NULL,
    vendor_id character varying(6) NOT NULL,
    dev_sub_sn character varying(6) NOT NULL,
    device_owner numeric(1,0),
    voip_phone text,
    serv_user_name character varying(100) DEFAULT NULL::character varying
);

ALTER TABLE ONLY public.tab_gw_device REPLICA IDENTITY FULL;


ALTER TABLE public.tab_gw_device OWNER TO gtmsmanager;

--
-- Name: COLUMN tab_gw_device.interface_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_gw_device.interface_id IS '0:自动发现
1:手工添加
2:批量导入
';


--
-- Name: COLUMN tab_gw_device.device_status; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_gw_device.device_status IS '-1: 删除
0: 未确认
1: 已经确认
';


--
-- Name: COLUMN tab_gw_device.cpe_allocatedstatus; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_gw_device.cpe_allocatedstatus IS '1:有
0:没有
';


--
-- Name: COLUMN tab_gw_device.cpe_currentstatus; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_gw_device.cpe_currentstatus IS '1：在线
0：下线
';


--
-- Name: COLUMN tab_gw_device.device_type; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_gw_device.device_type IS '现有数据：
e8-a
e8-b
e8-c
Navigator1-1
Navigator1-2
Navigator2-1
Navigator2-2
';


--
-- Name: COLUMN tab_gw_device.gw_type; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_gw_device.gw_type IS '1：家庭网关
2：企业网关';


--
-- Name: COLUMN tab_gw_device.device_owner; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_gw_device.device_owner IS '��������1������������0������������������1';


--
-- Name: COLUMN tab_gw_device.voip_phone; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_gw_device.voip_phone IS 'VOIP电话号码，多个号码用逗号分隔';


--
-- Name: COLUMN tab_gw_device.serv_user_name; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_gw_device.serv_user_name IS '服务用户名，如PPPOE账号';


--
-- Name: tab_gw_device_init; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_gw_device_init (
    device_id character varying(10) NOT NULL,
    oui character varying(6) NOT NULL,
    device_serialnumber character varying(64) NOT NULL,
    city_id character varying(20) NOT NULL,
    buy_time numeric(14,0),
    staff_id character varying(30),
    remark character varying(100),
    cpe_mac character varying(30),
    cpe_currentupdatetime numeric(10,0),
    gw_type numeric(1,0),
    dev_sub_sn character varying(6) NOT NULL,
    status numeric(1,0),
    vendor_name character varying(50),
    model_name character varying(50),
    add_date numeric(10,0),
    serial_no character varying(50)
);


ALTER TABLE public.tab_gw_device_init OWNER TO gtmsmanager;

--
-- Name: COLUMN tab_gw_device_init.gw_type; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_gw_device_init.gw_type IS '1����������
2����������';


--
-- Name: tab_gw_device_init_oui; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_gw_device_init_oui (
    id numeric(10,0) NOT NULL,
    oui character varying(50) NOT NULL,
    vendor_add character varying(50) NOT NULL,
    remark character varying(100),
    add_date numeric(10,0),
    vendor_name character varying(50),
    device_model character varying(50)
);


ALTER TABLE public.tab_gw_device_init_oui OWNER TO gtmsmanager;

--
-- Name: tab_gw_device_refuse; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_gw_device_refuse (
    oui character varying(6) NOT NULL,
    device_serialnumber character varying(64) NOT NULL,
    device_name character varying(80),
    city_id character varying(20) NOT NULL,
    complete_time numeric(10,0),
    buy_time numeric(14,0),
    remark character varying(100),
    loopback_ip character varying(30) NOT NULL,
    device_id_ex character varying(255),
    gw_type numeric(1,0),
    device_model_name character varying(50) NOT NULL,
    vendor_name character varying(50) NOT NULL,
    dev_sub_sn character varying(6) NOT NULL,
    specversion character varying(30),
    hardwareversion character varying(30),
    softwareversion character varying(30)
);


ALTER TABLE public.tab_gw_device_refuse OWNER TO gtmsmanager;

--
-- Name: COLUMN tab_gw_device_refuse.gw_type; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_gw_device_refuse.gw_type IS '1����������
2����������';


--
-- Name: tab_gw_device_scrap; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_gw_device_scrap (
    device_id character varying(10),
    username character varying(40),
    loid character varying(40),
    binddate numeric(10,0),
    city_id character varying(20),
    parent_id character varying(20),
    status numeric(2,0),
    is_charge numeric(1,0),
    complete_status numeric(2,0),
    ispt921g numeric(1,0),
    complete_time numeric(10,0),
    complete_type numeric(2,0),
    vendor_id character varying(6),
    model_id character varying(4),
    last_time numeric(10,0),
    change_netuser character varying(40),
    changed_netuser character varying(40),
    changed_vendor_id character varying(6),
    changed_model_id character varying(4),
    changed_last_time numeric(10,0)
);


ALTER TABLE public.tab_gw_device_scrap OWNER TO gtmsmanager;

--
-- Name: tab_gw_device_stbmac; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_gw_device_stbmac (
    device_id character varying(20) NOT NULL,
    stb_mac character varying(50) NOT NULL,
    update_time numeric(10,0),
    id numeric(10,0),
    lan_port numeric(2,0) NOT NULL
);


ALTER TABLE public.tab_gw_device_stbmac OWNER TO gtmsmanager;

--
-- Name: tab_gw_ht_megabytes; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_gw_ht_megabytes (
    id character varying(10) NOT NULL,
    device_sn character varying(64)
);


ALTER TABLE public.tab_gw_ht_megabytes OWNER TO gtmsmanager;

--
-- Name: tab_gw_identity; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_gw_identity (
    res_type character varying(50) NOT NULL,
    maxid numeric(15,0) NOT NULL
);


ALTER TABLE public.tab_gw_identity OWNER TO gtmsmanager;

--
-- Name: tab_gw_identity_bak; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_gw_identity_bak (
    res_type numeric(2,0) NOT NULL,
    maxid numeric(15,0) NOT NULL
);


ALTER TABLE public.tab_gw_identity_bak OWNER TO gtmsmanager;

--
-- Name: COLUMN tab_gw_identity_bak.res_type; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_gw_identity_bak.res_type IS '1:dev              tab_gw_device
2:segment      tp_gw_segment
11:ITMS 用户 tab_hgwcustomer
12:BBMS用户 tab_egwcustomer
21:EVDO数据卡厂商ID
22:EVDO数据卡型号ID
23:EVDO数据卡硬件ID
24:EVDO数据卡固件ID
25:EVDO数据卡ID
26:EVDO UIM卡ID';


--
-- Name: tab_gw_oper_type; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_gw_oper_type (
    oper_type_id numeric(4,0) NOT NULL,
    oper_type_name character varying(50) NOT NULL,
    oper_type_desc character varying(200),
    type numeric(2,0) NOT NULL
);


ALTER TABLE public.tab_gw_oper_type OWNER TO gtmsmanager;

--
-- Name: COLUMN tab_gw_oper_type.type; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_gw_oper_type.type IS '0：维护
1：手工工单需要显示
2：手工工单不要显示
';


--
-- Name: tab_gw_res_area; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_gw_res_area (
    res_type numeric(2,0) NOT NULL,
    res_id character varying(50) NOT NULL,
    area_id numeric(10,0) NOT NULL
);


ALTER TABLE public.tab_gw_res_area OWNER TO gtmsmanager;

--
-- Name: COLUMN tab_gw_res_area.res_type; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_gw_res_area.res_type IS '0：网段
1：设备
2：采集机资源
3：报表资源
4：用户视图资源
13：:配置任务ID
';


--
-- Name: tab_gw_serv_type; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_gw_serv_type (
    serv_type_id numeric(4,0) NOT NULL,
    serv_type_name character varying(50) NOT NULL,
    serv_type_desc character varying(200),
    type numeric(2,0) NOT NULL,
    serv_bss numeric(1,0) NOT NULL
);


ALTER TABLE public.tab_gw_serv_type OWNER TO gtmsmanager;

--
-- Name: COLUMN tab_gw_serv_type.type; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_gw_serv_type.type IS '0:维护业务
1:非维护业务';


--
-- Name: COLUMN tab_gw_serv_type.serv_bss; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_gw_serv_type.serv_bss IS '0:不是
1:是';


--
-- Name: tab_gw_stbid; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_gw_stbid (
    id numeric(10,0) NOT NULL,
    device_id character varying(10) NOT NULL,
    oui character varying(6) NOT NULL,
    device_serialnumber character varying(64) NOT NULL,
    vendor_id character varying(6) NOT NULL,
    device_model_id character varying(4) NOT NULL,
    id_code character varying(15) NOT NULL,
    stb_id character varying(100) NOT NULL,
    remark character varying(50)
);


ALTER TABLE public.tab_gw_stbid OWNER TO gtmsmanager;

--
-- Name: tab_gw_zhijia_device; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_gw_zhijia_device (
    province character varying(20),
    city character varying(20),
    area character varying(20),
    dev_type character varying(20),
    dev_factory character varying(20),
    dev_model character varying(50),
    hardwareversion character varying(50),
    softwareversion character varying(50),
    oui character varying(6),
    device_serialnumber character varying(64),
    sn character varying(80),
    datetime character varying(20)
);


ALTER TABLE public.tab_gw_zhijia_device OWNER TO gtmsmanager;

--
-- Name: tab_hgw_router; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_hgw_router (
    user_id numeric(10,0) NOT NULL,
    username character varying(40),
    app_type character varying(30) NOT NULL,
    router_id numeric(10,0) NOT NULL
);


ALTER TABLE public.tab_hgw_router OWNER TO gtmsmanager;

--
-- Name: tab_hgwcustomer; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_hgwcustomer (
    user_id numeric(10,0) NOT NULL,
    gather_id character varying(30) DEFAULT '-1'::character varying,
    username character varying(256) NOT NULL,
    passwd character varying(20),
    city_id character varying(20),
    cotno character varying(16),
    bill_type_id integer,
    next_bill_type_id integer,
    cust_type_id integer DEFAULT 0,
    user_type_id character varying(20),
    bindtype integer,
    virtualnum bigint,
    numcharacter character varying(10),
    access_style_id integer DEFAULT 1,
    aut_flag character varying(1) DEFAULT '0'::character varying,
    service_set character varying(255),
    realname character varying(50),
    sex character varying(2),
    cred_type_id integer,
    credno character varying(50),
    address character varying(100),
    office_id character varying(20) DEFAULT '0'::character varying,
    zone_id character varying(20) DEFAULT '0'::character varying,
    access_kind_id integer DEFAULT 0,
    trade_id integer DEFAULT 0,
    licenceregno character varying(50),
    occupation_id integer DEFAULT 0,
    education_id integer DEFAULT 0,
    vipcardno character varying(30),
    contractno character varying(50),
    linkman character varying(100),
    linkman_credno character varying(20),
    linkphone character varying(50),
    linkaddress character varying(500),
    mobile character varying(50),
    email character varying(100),
    agent character varying(20),
    agent_credno character varying(20),
    agentphone character varying(20),
    adsl_res integer,
    adsl_card character varying(30),
    adsl_dev character varying(30),
    adsl_ser character varying(30),
    isrepair character varying(1) DEFAULT '0'::character varying,
    bandwidth bigint DEFAULT 0,
    ipaddress character varying(15),
    overipnum integer,
    ipmask character varying(15),
    gateway character varying(15),
    macaddress character varying(20),
    device_id integer,
    device_ip character varying(15),
    device_shelf bigint DEFAULT 0,
    device_frame bigint,
    device_slot bigint DEFAULT '-1'::integer,
    device_port bigint,
    basdevice_id character varying(40),
    basdevice_ip character varying(15),
    basdevice_shelf smallint,
    basdevice_frame smallint,
    basdevice_slot integer,
    basdevice_port integer,
    vlanid character varying(20),
    workid character varying(20),
    user_state character varying(1) DEFAULT '1'::character varying NOT NULL,
    opendate bigint,
    onlinedate bigint,
    pausedate bigint,
    closedate bigint,
    updatetime bigint,
    staff_id character varying(30),
    remark character varying(100),
    phonenumber character varying(15),
    cableid character varying(10),
    bwlevel numeric(4,3),
    vpiid character varying(10),
    vciid integer,
    adsl_hl numeric(2,1),
    userline integer DEFAULT '-1'::integer,
    dslamserialno character varying(30),
    movedate bigint,
    dealdate bigint,
    opmode character varying(6),
    maxattdnrate bigint,
    upwidth bigint,
    oui character varying(6),
    device_serialnumber character varying(64),
    serv_type_id smallint DEFAULT 10 NOT NULL,
    max_user_number smallint,
    wan_value_1 character varying(200) DEFAULT '-1'::character varying,
    wan_value_2 character varying(200) DEFAULT '-1'::character varying,
    open_status smallint DEFAULT 0,
    wan_type smallint DEFAULT 1 NOT NULL,
    lan_num bigint,
    ssid_num bigint,
    work_model smallint,
    bind_port character varying(200),
    flag_pvc smallint DEFAULT 0 NOT NULL,
    binddate bigint,
    stat_bind_enab smallint DEFAULT 0 NOT NULL,
    bind_flag bigint,
    is_chk_bind smallint DEFAULT 0,
    sip_id integer,
    protocol integer,
    spec_id smallint DEFAULT 1,
    network_spec character varying(10),
    is_pon character varying(1),
    oui_productclass_sn character varying(50),
    customer_id character varying(100),
    sub_area_code character varying(20),
    is_active integer,
    user_sub_name character varying(10),
    longitude character varying(20),
    latitude character varying(20),
    is_tel_dev smallint
);


ALTER TABLE public.tab_hgwcustomer OWNER TO gtmsmanager;

--
-- Name: tab_hgwcustomer_bak; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_hgwcustomer_bak (
    user_id bigint NOT NULL,
    gather_id character varying(30),
    username character varying(40) NOT NULL,
    passwd character varying(20),
    city_id character varying(20),
    cotno character varying(16),
    bill_type_id integer,
    next_bill_type_id integer,
    cust_type_id integer,
    user_type_id character varying(20),
    bindtype integer,
    virtualnum bigint,
    numcharacter character varying(10),
    access_style_id integer,
    aut_flag character varying(1),
    service_set character varying(255),
    realname character varying(50),
    sex character varying(2),
    cred_type_id integer,
    credno character varying(50),
    address character varying(100),
    office_id character varying(20),
    zone_id character varying(20),
    access_kind_id integer,
    trade_id integer,
    licenceregno character varying(50),
    occupation_id integer,
    education_id integer,
    vipcardno character varying(30),
    contractno character varying(50),
    linkman character varying(100),
    linkman_credno character varying(20),
    linkphone character varying(50),
    linkaddress character varying(500),
    mobile character varying(50),
    email character varying(100),
    agent character varying(20),
    agent_credno character varying(20),
    agentphone character varying(20),
    adsl_res integer,
    adsl_card character varying(30),
    adsl_dev character varying(30),
    adsl_ser character varying(30),
    isrepair character varying(1),
    bandwidth bigint,
    ipaddress character varying(15),
    overipnum integer,
    ipmask character varying(15),
    gateway character varying(15),
    macaddress character varying(20),
    device_id character varying(100),
    device_ip character varying(15),
    device_shelf bigint,
    device_frame bigint,
    device_slot bigint,
    device_port bigint,
    basdevice_id character varying(40),
    basdevice_ip character varying(15),
    basdevice_shelf smallint,
    basdevice_frame smallint,
    basdevice_slot integer,
    basdevice_port integer,
    vlanid character varying(20),
    workid character varying(20),
    user_state character varying(1) DEFAULT '1'::character varying NOT NULL,
    opendate bigint,
    onlinedate bigint,
    pausedate bigint,
    closedate bigint,
    updatetime bigint,
    staff_id character varying(30),
    remark character varying(100),
    phonenumber character varying(15),
    cableid character varying(10),
    bwlevel numeric(4,3),
    vpiid character varying(10),
    vciid integer,
    adsl_hl numeric(2,1),
    userline integer,
    dslamserialno character varying(30),
    movedate bigint,
    dealdate bigint,
    opmode character varying(6),
    maxattdnrate bigint,
    upwidth bigint,
    oui character varying(6),
    device_serialnumber character varying(64),
    serv_type_id smallint DEFAULT 10 NOT NULL,
    max_user_number smallint,
    wan_value_1 character varying(200),
    wan_value_2 character varying(200),
    open_status smallint,
    wan_type smallint DEFAULT 1 NOT NULL,
    lan_num bigint,
    ssid_num bigint,
    work_model smallint,
    bind_port character varying(200),
    flag_pvc smallint DEFAULT 0 NOT NULL,
    binddate bigint,
    stat_bind_enab smallint DEFAULT 0 NOT NULL,
    bind_flag bigint,
    is_chk_bind smallint,
    sip_id integer,
    protocol integer,
    spec_id smallint,
    network_spec character varying(10),
    is_pon character varying(1),
    oui_productclass_sn character varying(50),
    customer_id character varying(100),
    sub_area_code character varying(20),
    is_active integer,
    user_sub_name character varying(10),
    longitude character varying(20),
    latitude character varying(20),
    is_tel_dev smallint
);


ALTER TABLE public.tab_hgwcustomer_bak OWNER TO gtmsmanager;

--
-- Name: tab_hqs_serv_param; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_hqs_serv_param (
    user_id numeric(10,0) NOT NULL,
    username character varying(40),
    serv_type_id numeric(4,0) NOT NULL,
    ipforwardlist text,
    qos_p_value character varying(10),
    business_id character varying(200),
    ip_type numeric(2,0) DEFAULT 3 NOT NULL,
    ipv6_address_origin character varying(20) DEFAULT 'AutoConfigured'::character varying,
    ipv6_prefix_origin character varying(20) DEFAULT 'PrefixDelegation'::character varying
);


ALTER TABLE public.tab_hqs_serv_param OWNER TO gtmsmanager;

--
-- Name: COLUMN tab_hqs_serv_param.ipforwardlist; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_hqs_serv_param.ipforwardlist IS 'InternetGatewayDevice.WANDevice.1.WANConnectionDevice.{j}.WANPPPConnection.1.X_CU_IPForwardList节点值';


--
-- Name: COLUMN tab_hqs_serv_param.qos_p_value; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_hqs_serv_param.qos_p_value IS 'InternetGatewayDevice.X_CU_Function.UplinkQoS.Classification.1.802-1_P_Value节点值';


--
-- Name: tab_http_diag_result_intf; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_http_diag_result_intf (
    device_id character varying(10) NOT NULL,
    cmdid character varying(64) NOT NULL,
    rstcode numeric(10,0),
    rstmsg character varying(64) NOT NULL,
    device_serialnumber character varying(64) NOT NULL,
    username character varying(40),
    speed character varying(20),
    avgsampledtotalvalues character varying(20),
    maxsampledtotalvalues character varying(20),
    transportstarttime character varying(30),
    transportendtime character varying(30),
    ip character varying(20),
    receivebyte character varying(20),
    tcprequesttime character varying(30),
    tcpresponsetime character varying(30),
    downurl character varying(64),
    updatetime numeric(10,0) NOT NULL,
    test_time numeric(10,0),
    wan_type character varying(20),
    loid character varying(64),
    testusername character varying(64)
);


ALTER TABLE public.tab_http_diag_result_intf OWNER TO gtmsmanager;

--
-- Name: tab_http_simplex_rate; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_http_simplex_rate (
    device_id character varying(10) NOT NULL,
    oui character varying(6),
    device_serialnumber character varying(64) NOT NULL,
    cmdid character varying(64) NOT NULL,
    rstcode numeric(10,0),
    rstmsg character varying(64) NOT NULL,
    username character varying(40),
    downlink character varying(20),
    avgsampledtotalvalues character varying(20),
    maxsampledtotalvalues character varying(20),
    transportstarttime character varying(30),
    transportendtime character varying(30),
    ip character varying(20),
    receivebyte character varying(20),
    tcprequesttime character varying(30),
    tcpresponsetime character varying(30),
    downurl character varying(64),
    updatetime numeric(10,0) NOT NULL,
    test_time numeric(10,0),
    wan_type character varying(20),
    loid character varying(64),
    status numeric(2,0) NOT NULL,
    testusername character varying(40),
    acc_loginame character varying(40)
);


ALTER TABLE public.tab_http_simplex_rate OWNER TO gtmsmanager;

--
-- Name: tab_http_special_speed_intf; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_http_special_speed_intf (
    device_id character varying(10) NOT NULL,
    cmdid character varying(64) NOT NULL,
    rstcode numeric(10,0),
    rstmsg character varying(64) NOT NULL,
    device_serialnumber character varying(64) NOT NULL,
    username character varying(40),
    netmask character varying(20),
    avgsampledtotalvalues character varying(20),
    maxsampledtotalvalues character varying(20),
    transportstarttime character varying(30),
    transportendtime character varying(30),
    ip character varying(20),
    receivebyte character varying(20),
    tcprequesttime character varying(30),
    tcpresponsetime character varying(30),
    downurl character varying(64),
    updatetime numeric(10,0) NOT NULL,
    test_time numeric(10,0),
    wan_type character varying(20),
    loid character varying(64),
    gateway character varying(64),
    clienttype numeric(10,0),
    dns character varying(64)
);


ALTER TABLE public.tab_http_special_speed_intf OWNER TO gtmsmanager;

--
-- Name: tab_http_speedtest; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_http_speedtest (
    device_id character varying(10) NOT NULL,
    test_time numeric(10,0) NOT NULL,
    download_url character varying(200),
    eth_priority character varying(1),
    rom_time character varying(40),
    bom_time character varying(40),
    eom_time character varying(40),
    test_bytes_rece character varying(10),
    total_bytes_rece character varying(10),
    tcp_req_time character varying(40),
    tcp_resp_time character varying(40),
    status numeric(6,0),
    resultdesc text,
    maxspeed character varying(40),
    avgspeed character varying(40),
    city_id character varying(40)
);


ALTER TABLE public.tab_http_speedtest OWNER TO gtmsmanager;

--
-- Name: tab_http_telnet_switch_record; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_http_telnet_switch_record (
    id character varying(32) NOT NULL,
    device_id character varying(64) NOT NULL,
    device_sn character varying(128),
    switch_type character varying(32) NOT NULL,
    switch_node character varying(256) NOT NULL,
    open_time bigint NOT NULL,
    close_time bigint,
    device_ip character varying(64)
);


ALTER TABLE public.tab_http_telnet_switch_record OWNER TO gtmsmanager;

--
-- Name: tab_http_test_user; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_http_test_user (
    testname character varying(20) NOT NULL,
    username character varying(20),
    password character varying(20),
    testrate numeric(5,0)
);


ALTER TABLE public.tab_http_test_user OWNER TO gtmsmanager;

--
-- Name: tab_import_data_temp; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_import_data_temp (
    import_data_id character varying(255) NOT NULL,
    file_name character varying(255),
    param_type character varying(255),
    param character varying(255),
    create_time numeric(30,0)
);


ALTER TABLE public.tab_import_data_temp OWNER TO gtmsmanager;

--
-- Name: tab_intf_speed_result; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_intf_speed_result (
    device_id character varying(10),
    device_serialnumber character varying(64),
    username character varying(40) NOT NULL,
    city_id character varying(20),
    speed character varying(20),
    avgsampledtotalvalues character varying(20),
    maxsampledtotalvalues character varying(20),
    avg2 character varying(20),
    max2 character varying(20),
    transportstarttime character varying(30),
    transportendtime character varying(30),
    ip character varying(20),
    receivebyte character varying(20),
    tcprequesttime character varying(30),
    tcpresponsetime character varying(30),
    speed_status numeric(2,0),
    updatetime numeric(10,0)
);


ALTER TABLE public.tab_intf_speed_result OWNER TO gtmsmanager;

--
-- Name: tab_ior; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_ior (
    object_name character varying(100) NOT NULL,
    object_poa character varying(100) NOT NULL,
    object_port numeric(20,0) NOT NULL,
    ior text NOT NULL
);


ALTER TABLE public.tab_ior OWNER TO gtmsmanager;

--
-- Name: tab_ipsec_serv_param; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_ipsec_serv_param (
    user_id numeric(10,0) NOT NULL,
    username character varying(40) NOT NULL,
    serv_type_id numeric(10,0) NOT NULL,
    serv_status numeric(2,0),
    enable numeric(2,0) NOT NULL,
    request_id character varying(40) NOT NULL,
    ipsec_type character varying(20),
    remote_domain character varying(20),
    remote_subnet character varying(40),
    local_subnet character varying(20),
    remote_ip character varying(20),
    exchange_mode character varying(40),
    ike_auth_algorithm character varying(40),
    ike_auth__method character varying(20),
    ike_encryption_algorithm character varying(40),
    ike_dhgroup character varying(10),
    ike_idtype character varying(10),
    ike_localname character varying(10),
    ike_remotename character varying(10),
    ike_presharekey character varying(128),
    ipsec_out_interface character varying(20),
    ipsec_encapsulation_mode character varying(10),
    ipsec_transform character varying(10),
    esp_auth_algorithem character varying(10) NOT NULL,
    esp_encrypt_algorithm character varying(10),
    ipsec_pfs character varying(10),
    ike_saperiod numeric(10,0),
    ipsec_satime_period numeric(10,0),
    ipsec_satraffic_period numeric(10,0),
    ah_auth_algorithm character varying(10),
    dpd_enable numeric(2,0),
    dpd_threshold numeric(10,0),
    dpd_retry numeric(10,0),
    open_date numeric(10,0) NOT NULL,
    updatetime numeric(10,0) NOT NULL,
    completedate numeric(10,0),
    open_status numeric(2,0) NOT NULL
);


ALTER TABLE public.tab_ipsec_serv_param OWNER TO gtmsmanager;

--
-- Name: tab_iptv_serv_param; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_iptv_serv_param (
    user_id numeric(10,0) NOT NULL,
    serv_account character varying(40) NOT NULL,
    serv_pwd character varying(40) NOT NULL,
    pppoe_user character varying(40) NOT NULL,
    pppoe_pwd character varying(40) NOT NULL,
    add_time numeric(10,0) NOT NULL,
    update_time numeric(10,0) NOT NULL
);


ALTER TABLE public.tab_iptv_serv_param OWNER TO gtmsmanager;

--
-- Name: tab_iptv_user; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_iptv_user (
    user_id numeric(10,0) NOT NULL,
    serv_type_id numeric(4,0) NOT NULL,
    username character varying(40) NOT NULL,
    serv_status numeric(1,0) NOT NULL,
    passwd character varying(40),
    wan_type numeric(2,0) NOT NULL,
    vpiid character varying(50),
    vciid numeric(6,0),
    vlanid character varying(50),
    ipaddress character varying(15),
    ipmask character varying(15),
    gateway character varying(15),
    adsl_ser character varying(15),
    open_status numeric(1,0) NOT NULL,
    opendate numeric(10,0),
    pausedate numeric(10,0),
    closedate numeric(10,0),
    updatetime numeric(10,0),
    completedate numeric(10,0),
    bas_ip character varying(160),
    dev_mac character varying(50),
    reform_flag numeric(1,0),
    assess_flag numeric(1,0),
    radius_onlinedate numeric(10,0)
);


ALTER TABLE public.tab_iptv_user OWNER TO gtmsmanager;

--
-- Name: tab_item; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_item (
    sequence numeric(6,0) NOT NULL,
    item_id character varying(36) NOT NULL,
    item_name character varying(100) NOT NULL,
    item_url character varying(255) NOT NULL,
    item_desc character varying(255),
    item_visual character(1) NOT NULL
);


ALTER TABLE public.tab_item OWNER TO gtmsmanager;

--
-- Name: tab_item_role; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_item_role (
    sequence numeric(6,0),
    item_id character varying(36) NOT NULL,
    role_id numeric(3,0) NOT NULL
);


ALTER TABLE public.tab_item_role OWNER TO gtmsmanager;

--
-- Name: tab_lan_speed_report; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_lan_speed_report (
    username character varying(50) NOT NULL,
    device_id character varying(10) NOT NULL,
    max_bit_rate character varying(8),
    city_id character varying(20),
    city_name character varying(20),
    gather_time numeric(10,0),
    update_time numeric(10,0) NOT NULL
);


ALTER TABLE public.tab_lan_speed_report OWNER TO gtmsmanager;

--
-- Name: COLUMN tab_lan_speed_report.username; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_lan_speed_report.username IS 'loid';


--
-- Name: COLUMN tab_lan_speed_report.device_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_lan_speed_report.device_id IS 'device_id';


--
-- Name: COLUMN tab_lan_speed_report.max_bit_rate; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_lan_speed_report.max_bit_rate IS '速率';


--
-- Name: COLUMN tab_lan_speed_report.city_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_lan_speed_report.city_id IS '设备属地，对应设备表中city_id';


--
-- Name: COLUMN tab_lan_speed_report.city_name; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_lan_speed_report.city_name IS '设备地市属地';


--
-- Name: COLUMN tab_lan_speed_report.gather_time; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_lan_speed_report.gather_time IS '采集时间';


--
-- Name: COLUMN tab_lan_speed_report.update_time; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_lan_speed_report.update_time IS '更新时间';


--
-- Name: tab_modify_vlan_task; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_modify_vlan_task (
    task_id numeric(10,0) NOT NULL,
    acc_oid numeric(14,0) NOT NULL,
    add_time numeric(10,0) NOT NULL,
    service_id numeric(4,0) NOT NULL,
    strategy_type numeric(2,0),
    param text,
    type numeric(1,0) NOT NULL,
    status numeric(1,0) NOT NULL
);


ALTER TABLE public.tab_modify_vlan_task OWNER TO gtmsmanager;

--
-- Name: tab_modify_vlan_task_dev; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_modify_vlan_task_dev (
    task_id numeric(10,0) NOT NULL,
    file_username character varying(64) NOT NULL,
    loid character varying(64),
    netusername character varying(64),
    device_id character varying(10),
    device_serialnumber character varying(64),
    oui character varying(6),
    result_id numeric(10,0),
    status numeric(3,0),
    add_time numeric(10,0) NOT NULL,
    update_time numeric(10,0) NOT NULL,
    res character varying(200)
);


ALTER TABLE public.tab_modify_vlan_task_dev OWNER TO gtmsmanager;

--
-- Name: tab_monthgather_device; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_monthgather_device (
    device_id character varying(10) NOT NULL,
    username character varying(40) NOT NULL,
    status numeric(1,0) NOT NULL,
    device_serialnumber character varying(64) NOT NULL,
    update_time numeric(10,0)
);


ALTER TABLE public.tab_monthgather_device OWNER TO gtmsmanager;

--
-- Name: tab_monthgather_device_manual; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_monthgather_device_manual (
    device_id character varying(64) NOT NULL,
    status character varying(10)
);

ALTER TABLE ONLY public.tab_monthgather_device_manual REPLICA IDENTITY FULL;


ALTER TABLE public.tab_monthgather_device_manual OWNER TO gtmsmanager;

--
-- Name: tab_net_serv_param; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_net_serv_param (
    user_id numeric(10,0) NOT NULL,
    username character varying(40),
    ip_type numeric(2,0) DEFAULT 0 NOT NULL,
    dslite_enable numeric(2,0) DEFAULT 0 NOT NULL,
    aftr_mode numeric(2,0),
    aftr_ip character varying(40),
    ipv6_address_origin character varying(20),
    ipv6_address character varying(40),
    ipv6_dns character varying(40),
    ipv6_prefix_origin character varying(20),
    ipv6_prefix character varying(40),
    max_net_num numeric(2,0),
    dpi numeric(1,0),
    serv_type_id numeric(4,0) NOT NULL,
    net_conn_method numeric(1,0),
    untreated_ip_type numeric(1,0),
    special_line_mark numeric(1,0),
    vpdn numeric(1,0) DEFAULT 0 NOT NULL,
    up_bandwidth character varying(15),
    down_bandwidth character varying(15),
    next_bind_port character varying(500),
    ssid_usernumber character varying(50),
    ssid character varying(50),
    product_id character varying(40),
    dhcp_enable smallint DEFAULT '-1'::integer,
    ip_forward_list character varying(500),
    gatewaynum character varying(10),
    lan_ip character varying(15),
    lan_ip_min character varying(15),
    lan_ip_max character varying(15),
    dhcp_start_ip character varying(40),
    dhcp_end_ip character varying(40),
    nat_enabled smallint,
    lansubnetmask character varying(20) DEFAULT '255.255.255.252'::character varying
);


ALTER TABLE public.tab_net_serv_param OWNER TO gtmsmanager;

--
-- Name: COLUMN tab_net_serv_param.ip_type; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_net_serv_param.ip_type IS '1：ipv4 2：ipv6 3：ipv4+ipv6';


--
-- Name: COLUMN tab_net_serv_param.dslite_enable; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_net_serv_param.dslite_enable IS '0：否   1：是';


--
-- Name: COLUMN tab_net_serv_param.aftr_mode; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_net_serv_param.aftr_mode IS ' 0，自动获取  1，手工设置';


--
-- Name: COLUMN tab_net_serv_param.ipv6_address_origin; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_net_serv_param.ipv6_address_origin IS 'AutoConfigured
DHCPv6
 Static
None';


--
-- Name: COLUMN tab_net_serv_param.ipv6_prefix_origin; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_net_serv_param.ipv6_prefix_origin IS 'PrefixDelegation
RouterAdvertisement
Static
None';


--
-- Name: COLUMN tab_net_serv_param.dpi; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_net_serv_param.dpi IS '1：开启 0：关闭';


--
-- Name: COLUMN tab_net_serv_param.untreated_ip_type; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_net_serv_param.untreated_ip_type IS ' 0-����������1-����������2-����������3-��������';


--
-- Name: tab_netacc_spead; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_netacc_spead (
    username character varying(50) NOT NULL,
    uplink character varying(50),
    downlink character varying(50) NOT NULL,
    update_time numeric(10,0) NOT NULL
);


ALTER TABLE public.tab_netacc_spead OWNER TO gtmsmanager;

--
-- Name: tab_netspeed_param; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_netspeed_param (
    user_id numeric(10,0) NOT NULL,
    serv_type_id numeric(4,0) NOT NULL,
    username character varying(40),
    speed character varying(40),
    update_time numeric(11,0)
);


ALTER TABLE public.tab_netspeed_param OWNER TO gtmsmanager;

--
-- Name: tab_office; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_office (
    office_id character varying(20) NOT NULL,
    office_name character varying(50) NOT NULL,
    staff_id character varying(30),
    remark character varying(100)
);


ALTER TABLE public.tab_office OWNER TO gtmsmanager;

--
-- Name: tab_oper_log; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_oper_log (
    acc_oid numeric(10,0) NOT NULL,
    acc_login_ip character varying(20) NOT NULL,
    operationlog_type numeric(1,0) NOT NULL,
    operation_time numeric(10,0),
    operation_name character varying(50),
    operation_object character varying(50),
    operation_content text,
    operation_device character varying(50),
    operation_result character varying(50),
    result_id numeric(1,0),
    log_sub_type numeric(1,0)
);


ALTER TABLE public.tab_oper_log OWNER TO gtmsmanager;

--
-- Name: COLUMN tab_oper_log.operationlog_type; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_oper_log.operationlog_type IS '1:WEB
2:设备
3:工单
4:接口
';


--
-- Name: COLUMN tab_oper_log.operation_time; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_oper_log.operation_time IS '秒';


--
-- Name: COLUMN tab_oper_log.operation_name; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_oper_log.operation_name IS '0:其它
1:查询
2:配置
3:诊断
';


--
-- Name: COLUMN tab_oper_log.operation_object; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_oper_log.operation_object IS '1、WEB菜单名字
2、username
';


--
-- Name: COLUMN tab_oper_log.operation_content; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_oper_log.operation_content IS '日志类型为2:
操作节点配的值
日志类型为3、4:
接口、工单所有数据
';


--
-- Name: COLUMN tab_oper_log.result_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_oper_log.result_id IS '1:成功
0:失败
';


--
-- Name: tab_oss_devicebaseinfo; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_oss_devicebaseinfo (
    device_id character varying(64),
    pppoename character varying(128),
    oui_sn character varying(64),
    modelname character varying(64),
    serialnumber character varying(64),
    x_cu_serialnumber character varying(64),
    loid character varying(64),
    numberofsubuser character varying(10),
    description character varying(500),
    productclass character varying(64),
    manufacturer character varying(64),
    hardwareversion character varying(64),
    softwareversion character varying(64),
    wantype character varying(64),
    wandevicenumberofentries character varying(10),
    landevicenumberofentries character varying(10),
    x_cu_potsdevicenumber character varying(10),
    wlan character varying(10),
    ipprotocolversion character varying(64),
    x_cu_band character varying(64),
    speedtest character varying(10),
    x_cu_os character varying(64),
    inserttime integer
);


ALTER TABLE public.tab_oss_devicebaseinfo OWNER TO gtmsmanager;

--
-- Name: tab_oss_dslperformance; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_oss_dslperformance (
    device_id character varying(64) NOT NULL,
    pppoename character varying(64),
    devsn character varying(64),
    upstreamcurrrate character varying(64),
    downstreamcurrrate character varying(64),
    upstreammaxrate character varying(64),
    downstreammaxrate character varying(64),
    upstreamnoisemargin character varying(64),
    downstreamnoisemargin character varying(64),
    upstreampower character varying(64),
    dlineattenuation character varying(64),
    ulineattenuation character varying(64),
    inserttime integer
);


ALTER TABLE public.tab_oss_dslperformance OWNER TO gtmsmanager;

--
-- Name: tab_oss_ontinfo; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_oss_ontinfo (
    device_id character varying(64) NOT NULL,
    serialnumber character varying(255),
    enable character varying(10),
    username character varying(255),
    directorynumber1 character varying(50),
    directorynumber2 character varying(50),
    externalipaddress_hsi character varying(50),
    dnsservers_hsi text,
    externalipaddress_voip character varying(50),
    dnsservers_voip text,
    externalipaddress_iptv character varying(50),
    dnsservers_iptv text,
    txpower character varying(50),
    rxpower character varying(50),
    biascurrent character varying(50),
    transceivertemperature character varying(50),
    supplyvoltage character varying(50),
    manufacturer character varying(255),
    memused character varying(50),
    cpuused character varying(50),
    uptime character varying(50),
    softwareversion character varying(100),
    hardwareversion character varying(100),
    modelname character varying(100),
    regulatorydomain character varying(50),
    created_time bigint
);


ALTER TABLE public.tab_oss_ontinfo OWNER TO gtmsmanager;

--
-- Name: tab_oss_performance; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_oss_performance (
    device_id character varying(64) NOT NULL,
    devsn character varying(64),
    pppoename character varying(64),
    upstreamcurrrate character varying(64),
    downstreamcurrrate character varying(64),
    upstreammaxrate character varying(64),
    downstreammaxrate character varying(64),
    upstreamnoisemargin character varying(64),
    downstreamnoisemargin character varying(64),
    upstreampower character varying(64),
    dlineattenuation character varying(64),
    ulineattenuation character varying(64),
    rssi character varying(64),
    rsrp character varying(64),
    rsrq character varying(64),
    inserttime integer NOT NULL
);


ALTER TABLE public.tab_oss_performance OWNER TO gtmsmanager;

--
-- Name: COLUMN tab_oss_performance.upstreamcurrrate; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_oss_performance.upstreamcurrrate IS '上行速率';


--
-- Name: COLUMN tab_oss_performance.downstreamcurrrate; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_oss_performance.downstreamcurrrate IS '下行速率';


--
-- Name: COLUMN tab_oss_performance.upstreammaxrate; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_oss_performance.upstreammaxrate IS '上行最大速率';


--
-- Name: COLUMN tab_oss_performance.downstreammaxrate; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_oss_performance.downstreammaxrate IS '下行最大速率';


--
-- Name: COLUMN tab_oss_performance.upstreamnoisemargin; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_oss_performance.upstreamnoisemargin IS '上行信噪比';


--
-- Name: COLUMN tab_oss_performance.downstreamnoisemargin; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_oss_performance.downstreamnoisemargin IS '下行信噪比';


--
-- Name: COLUMN tab_oss_performance.upstreampower; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_oss_performance.upstreampower IS '输出功率';


--
-- Name: COLUMN tab_oss_performance.dlineattenuation; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_oss_performance.dlineattenuation IS '下行线路衰减';


--
-- Name: COLUMN tab_oss_performance.ulineattenuation; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_oss_performance.ulineattenuation IS '上行线路衰减';


--
-- Name: COLUMN tab_oss_performance.rssi; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_oss_performance.rssi IS '信号接收强度';


--
-- Name: COLUMN tab_oss_performance.rsrp; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_oss_performance.rsrp IS '信号接收功率';


--
-- Name: COLUMN tab_oss_performance.rsrq; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_oss_performance.rsrq IS '信号接收质量';


--
-- Name: COLUMN tab_oss_performance.inserttime; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_oss_performance.inserttime IS '插入时间';


--
-- Name: tab_oss_wifiassociatedinfo; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_oss_wifiassociatedinfo (
    device_id character varying(64) NOT NULL,
    serialnumber character varying(128),
    landevice_j integer NOT NULL,
    associateddevice_k integer NOT NULL,
    associateddevicemacaddress character varying(32),
    associateddeviceauthenticationstate character varying(32),
    associateddevicedescription character varying(128),
    uptime character varying(50),
    rxrate character varying(50),
    txrate character varying(50),
    snr character varying(50),
    rssi character varying(50),
    noise character varying(50),
    inserttime bigint
);


ALTER TABLE public.tab_oss_wifiassociatedinfo OWNER TO gtmsmanager;

--
-- Name: tab_oss_wifissidinfo; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_oss_wifissidinfo (
    device_id character varying(64) NOT NULL,
    serialnumber character varying(128),
    landevice_j integer NOT NULL,
    enable integer,
    status character varying(32),
    radioenabled integer,
    standard character varying(32),
    channel integer,
    autochannelenable integer,
    transmitpower integer,
    ssidadvertisementenabled integer,
    ssid character varying(128),
    bssid character varying(32),
    bandwidth character varying(32),
    inserttime bigint
);


ALTER TABLE public.tab_oss_wifissidinfo OWNER TO gtmsmanager;

--
-- Name: tab_para; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_para (
    para_id numeric(10,0) NOT NULL,
    para_name character varying(255) NOT NULL,
    para_type_id numeric(10,0) NOT NULL,
    para_desc character varying(255)
);


ALTER TABLE public.tab_para OWNER TO gtmsmanager;

--
-- Name: tab_para_type; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_para_type (
    para_type_id numeric(10,0) NOT NULL,
    para_type_name character varying(50) NOT NULL,
    is_array numeric(1,0) NOT NULL,
    para_type_desc character varying(255)
);


ALTER TABLE public.tab_para_type OWNER TO gtmsmanager;

--
-- Name: COLUMN tab_para_type.is_array; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_para_type.is_array IS '1-数组
2-非数组类型
0- 其他
';


--
-- Name: tab_performance_alarm; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_performance_alarm (
    id integer NOT NULL,
    device_id character varying(64) NOT NULL,
    device_serialnumber character varying(64) NOT NULL,
    performance_id integer NOT NULL,
    performance_name character varying(64) NOT NULL,
    threshold_value integer NOT NULL,
    alarm_value numeric(64,0) NOT NULL,
    alarm_time integer NOT NULL,
    alarm_date integer NOT NULL
);


ALTER TABLE public.tab_performance_alarm OWNER TO gtmsmanager;

--
-- Name: COLUMN tab_performance_alarm.threshold_value; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_performance_alarm.threshold_value IS '阈值';


--
-- Name: COLUMN tab_performance_alarm.alarm_value; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_performance_alarm.alarm_value IS '设备节点值';


--
-- Name: tab_performance_mangement; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_performance_mangement (
    id integer NOT NULL,
    performance_name character varying(64) NOT NULL,
    path character varying(255) NOT NULL,
    threshold_value integer NOT NULL,
    alarm_compare integer NOT NULL,
    is_alarm integer DEFAULT 1 NOT NULL,
    add_time integer NOT NULL,
    show_value character varying(32)
);


ALTER TABLE public.tab_performance_mangement OWNER TO gtmsmanager;

--
-- Name: COLUMN tab_performance_mangement.path; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_performance_mangement.path IS '匹配节点路径';


--
-- Name: COLUMN tab_performance_mangement.threshold_value; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_performance_mangement.threshold_value IS '阈值';


--
-- Name: COLUMN tab_performance_mangement.alarm_compare; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_performance_mangement.alarm_compare IS 'means the alarm value compare with the threshold value:1-more;2-less';


--
-- Name: COLUMN tab_performance_mangement.is_alarm; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_performance_mangement.is_alarm IS '0:关闭 1：开启';


--
-- Name: tab_permission_collect; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_permission_collect (
    id character varying(64) NOT NULL,
    name character varying(128),
    path character varying(256),
    user_id character varying(64),
    update_time integer,
    create_time integer
);


ALTER TABLE public.tab_permission_collect OWNER TO gtmsmanager;

--
-- Name: tab_persons; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_persons (
    per_acc_oid numeric(10,0) NOT NULL,
    per_searchcode character varying(80),
    per_name character varying(40),
    per_lastname character varying(40),
    per_gender character varying(5),
    per_title character varying(10),
    per_jobtitle character varying(40),
    per_birthdate timestamp without time zone,
    per_phone character varying(60),
    per_mobile character varying(60),
    per_email character varying(80),
    per_city text,
    per_dep_oid numeric(18,0),
    per_category character varying(40),
    per_remark character varying(255)
);


ALTER TABLE public.tab_persons OWNER TO gtmsmanager;

--
-- Name: tab_process; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_process (
    gather_id character varying(10) NOT NULL,
    process_name character varying(50) NOT NULL,
    process_number numeric(10,0) NOT NULL,
    _no_pk_hash character varying(64)
);

ALTER TABLE ONLY public.tab_process REPLICA IDENTITY FULL;


ALTER TABLE public.tab_process OWNER TO gtmsmanager;

--
-- Name: tab_process_config; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_process_config (
    gather_id character varying(30) NOT NULL,
    process_name character varying(50) NOT NULL,
    location character varying(10) NOT NULL,
    para_item character varying(255) NOT NULL,
    para_context character varying(255) NOT NULL
);


ALTER TABLE public.tab_process_config OWNER TO gtmsmanager;

--
-- Name: COLUMN tab_process_config.para_item; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_process_config.para_item IS '必须至少两项配置
LocalName
LocalPoaName
';


--
-- Name: tab_process_desc; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_process_desc (
    gather_id character varying(30) NOT NULL,
    descr character varying(255) NOT NULL,
    city_id character varying(20),
    area_id numeric(10,0)
);


ALTER TABLE public.tab_process_desc OWNER TO gtmsmanager;

--
-- Name: tab_quality_analysis_id_seq; Type: SEQUENCE; Schema: public; Owner: gtmsmanager
--

CREATE SEQUENCE public.tab_quality_analysis_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.tab_quality_analysis_id_seq OWNER TO gtmsmanager;

--
-- Name: tab_quality_issue_analysis; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_quality_issue_analysis (
    id integer NOT NULL,
    user_account character varying(64),
    device_id character varying(100) NOT NULL,
    device_type character varying(20) NOT NULL,
    vendor character varying(50),
    model character varying(100),
    quality_issue_label character varying(20) NOT NULL,
    is_fixed integer,
    create_time bigint,
    last_update_time integer,
    fixed_time integer
);


ALTER TABLE public.tab_quality_issue_analysis OWNER TO gtmsmanager;

--
-- Name: TABLE tab_quality_issue_analysis; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON TABLE public.tab_quality_issue_analysis IS '质差分析记录表';


--
-- Name: COLUMN tab_quality_issue_analysis.id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_quality_issue_analysis.id IS '主键';


--
-- Name: COLUMN tab_quality_issue_analysis.user_account; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_quality_issue_analysis.user_account IS '用户账号';


--
-- Name: COLUMN tab_quality_issue_analysis.device_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_quality_issue_analysis.device_id IS '设备唯一标识';


--
-- Name: COLUMN tab_quality_issue_analysis.device_type; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_quality_issue_analysis.device_type IS '设备类型（ap：路由器；onu：光猫）1是ONT 2是AP';


--
-- Name: COLUMN tab_quality_issue_analysis.vendor; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_quality_issue_analysis.vendor IS '厂商ID';


--
-- Name: COLUMN tab_quality_issue_analysis.model; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_quality_issue_analysis.model IS '型号ID';


--
-- Name: COLUMN tab_quality_issue_analysis.quality_issue_label; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_quality_issue_analysis.quality_issue_label IS '质差问题编码
W1001：Wi-Fi覆盖差；
W1003：Wi-Fi干扰强；
W1004：Wi-Fi参数异常；
D2001：物理线路损坏；
D2002：AP异品牌';


--
-- Name: COLUMN tab_quality_issue_analysis.is_fixed; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_quality_issue_analysis.is_fixed IS '是否已经修复 1=是；0=否，null不适用';


--
-- Name: COLUMN tab_quality_issue_analysis.create_time; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_quality_issue_analysis.create_time IS '创建时间';


--
-- Name: COLUMN tab_quality_issue_analysis.last_update_time; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_quality_issue_analysis.last_update_time IS '最近更新时间';


--
-- Name: COLUMN tab_quality_issue_analysis.fixed_time; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_quality_issue_analysis.fixed_time IS '问题修复时间';


--
-- Name: tab_quality_issue_analysis_detail_id_seq; Type: SEQUENCE; Schema: public; Owner: gtmsmanager
--

CREATE SEQUENCE public.tab_quality_issue_analysis_detail_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.tab_quality_issue_analysis_detail_id_seq OWNER TO gtmsmanager;

--
-- Name: tab_quality_issue_analysis_detail; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_quality_issue_analysis_detail (
    id bigint DEFAULT nextval('public.tab_quality_issue_analysis_detail_id_seq'::regclass) NOT NULL,
    quality_issue_label character varying(20),
    main_issue_id bigint NOT NULL,
    deduct_score integer,
    create_time bigint,
    node_ijk character varying(20)
);


ALTER TABLE public.tab_quality_issue_analysis_detail OWNER TO gtmsmanager;

--
-- Name: TABLE tab_quality_issue_analysis_detail; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON TABLE public.tab_quality_issue_analysis_detail IS '质差分析详情记录';


--
-- Name: COLUMN tab_quality_issue_analysis_detail.id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_quality_issue_analysis_detail.id IS '主键';


--
-- Name: COLUMN tab_quality_issue_analysis_detail.quality_issue_label; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_quality_issue_analysis_detail.quality_issue_label IS '质差标识';


--
-- Name: COLUMN tab_quality_issue_analysis_detail.main_issue_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_quality_issue_analysis_detail.main_issue_id IS '质差大项记录ID';


--
-- Name: COLUMN tab_quality_issue_analysis_detail.deduct_score; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_quality_issue_analysis_detail.deduct_score IS '扣分值';


--
-- Name: COLUMN tab_quality_issue_analysis_detail.create_time; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_quality_issue_analysis_detail.create_time IS '创建时间';


--
-- Name: COLUMN tab_quality_issue_analysis_detail.node_ijk; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_quality_issue_analysis_detail.node_ijk IS '节点索引';


--
-- Name: tab_quality_issue_fixed_history; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_quality_issue_fixed_history (
    id integer NOT NULL,
    user_account character varying(64),
    device_id character varying(100),
    device_type character varying(20),
    vendor character varying(50),
    model character varying(100),
    quality_issue_label character varying(20),
    is_fixed integer,
    create_time bigint,
    fixed_time integer,
    result_detail character varying(200)
);


ALTER TABLE public.tab_quality_issue_fixed_history OWNER TO gtmsmanager;

--
-- Name: tab_quality_issue_fixed_history_id_seq; Type: SEQUENCE; Schema: public; Owner: gtmsmanager
--

CREATE SEQUENCE public.tab_quality_issue_fixed_history_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.tab_quality_issue_fixed_history_id_seq OWNER TO gtmsmanager;

--
-- Name: tab_quality_issue_kpi_rule_id_seq; Type: SEQUENCE; Schema: public; Owner: gtmsmanager
--

CREATE SEQUENCE public.tab_quality_issue_kpi_rule_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.tab_quality_issue_kpi_rule_id_seq OWNER TO gtmsmanager;

--
-- Name: tab_quality_issue_kpi_rule; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_quality_issue_kpi_rule (
    id integer DEFAULT nextval('public.tab_quality_issue_kpi_rule_id_seq'::regclass) NOT NULL,
    quality_issue_tag character varying(100) NOT NULL,
    quality_issue_code character varying(50) NOT NULL,
    quality_subitem character varying(50),
    indicator_name character varying(255) NOT NULL,
    indicator_identifier character varying(100) NOT NULL,
    indicator_node character varying(255),
    node_identifier character varying(100),
    indicator_threshold character varying(50),
    threshold_comparison_rule character varying(50),
    involves_multiple_records character varying(1) DEFAULT 'N'::character varying,
    multiple_records_percentage character varying(10),
    deduction_score integer DEFAULT 0,
    valid integer
);


ALTER TABLE public.tab_quality_issue_kpi_rule OWNER TO gtmsmanager;

--
-- Name: TABLE tab_quality_issue_kpi_rule; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON TABLE public.tab_quality_issue_kpi_rule IS '质差KPI规则表';


--
-- Name: COLUMN tab_quality_issue_kpi_rule.id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_quality_issue_kpi_rule.id IS '自增主键ID';


--
-- Name: COLUMN tab_quality_issue_kpi_rule.quality_issue_tag; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_quality_issue_kpi_rule.quality_issue_tag IS '质差标签';


--
-- Name: COLUMN tab_quality_issue_kpi_rule.quality_issue_code; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_quality_issue_kpi_rule.quality_issue_code IS '质差标签编码';


--
-- Name: COLUMN tab_quality_issue_kpi_rule.quality_subitem; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_quality_issue_kpi_rule.quality_subitem IS '质差子项';


--
-- Name: COLUMN tab_quality_issue_kpi_rule.indicator_name; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_quality_issue_kpi_rule.indicator_name IS '指标名称';


--
-- Name: COLUMN tab_quality_issue_kpi_rule.indicator_identifier; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_quality_issue_kpi_rule.indicator_identifier IS '指标标识';


--
-- Name: COLUMN tab_quality_issue_kpi_rule.indicator_node; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_quality_issue_kpi_rule.indicator_node IS '指标节点';


--
-- Name: COLUMN tab_quality_issue_kpi_rule.node_identifier; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_quality_issue_kpi_rule.node_identifier IS '节点标识';


--
-- Name: COLUMN tab_quality_issue_kpi_rule.indicator_threshold; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_quality_issue_kpi_rule.indicator_threshold IS '指标阈值';


--
-- Name: COLUMN tab_quality_issue_kpi_rule.threshold_comparison_rule; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_quality_issue_kpi_rule.threshold_comparison_rule IS '阈值比较规则';


--
-- Name: COLUMN tab_quality_issue_kpi_rule.involves_multiple_records; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_quality_issue_kpi_rule.involves_multiple_records IS '是否涉及多条记录';


--
-- Name: COLUMN tab_quality_issue_kpi_rule.multiple_records_percentage; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_quality_issue_kpi_rule.multiple_records_percentage IS '多条记录质差百分比';


--
-- Name: COLUMN tab_quality_issue_kpi_rule.deduction_score; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_quality_issue_kpi_rule.deduction_score IS '扣分';


--
-- Name: COLUMN tab_quality_issue_kpi_rule.valid; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_quality_issue_kpi_rule.valid IS '是否有效（0=无效，1=有效）';


--
-- Name: tab_quality_issue_kpi_rule_bak; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_quality_issue_kpi_rule_bak (
    id integer,
    quality_issue_tag character varying(100),
    quality_issue_code character varying(50),
    quality_subitem character varying(50),
    indicator_name character varying(255),
    indicator_identifier character varying(100),
    indicator_node character varying(255),
    node_identifier character varying(100),
    indicator_threshold character varying(50),
    threshold_comparison_rule character varying(50),
    involves_multiple_records character varying(1),
    multiple_records_percentage character varying(10),
    deduction_score integer,
    valid integer
);


ALTER TABLE public.tab_quality_issue_kpi_rule_bak OWNER TO gtmsmanager;

--
-- Name: tab_quality_issue_repair_his_id_seq; Type: SEQUENCE; Schema: public; Owner: gtmsmanager
--

CREATE SEQUENCE public.tab_quality_issue_repair_his_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.tab_quality_issue_repair_his_id_seq OWNER TO gtmsmanager;

--
-- Name: tab_quality_issue_repair_his; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_quality_issue_repair_his (
    id bigint DEFAULT nextval('public.tab_quality_issue_repair_his_id_seq'::regclass) NOT NULL,
    measures_id integer NOT NULL,
    fault_code character varying(20),
    result character varying(200),
    create_time bigint,
    repair_issue_his_id integer
);


ALTER TABLE public.tab_quality_issue_repair_his OWNER TO gtmsmanager;

--
-- Name: TABLE tab_quality_issue_repair_his; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON TABLE public.tab_quality_issue_repair_his IS '质差问题修复措施记录';


--
-- Name: COLUMN tab_quality_issue_repair_his.id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_quality_issue_repair_his.id IS '主键';


--
-- Name: COLUMN tab_quality_issue_repair_his.measures_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_quality_issue_repair_his.measures_id IS '采取的修复措施ID';


--
-- Name: COLUMN tab_quality_issue_repair_his.fault_code; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_quality_issue_repair_his.fault_code IS '错误码';


--
-- Name: COLUMN tab_quality_issue_repair_his.result; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_quality_issue_repair_his.result IS '修复结果';


--
-- Name: COLUMN tab_quality_issue_repair_his.create_time; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_quality_issue_repair_his.create_time IS '创建时间';


--
-- Name: tab_quality_issue_suggestion; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_quality_issue_suggestion (
    id integer NOT NULL,
    issue_label_code character varying(20),
    issue_label_value character varying(100),
    suggestion_code character varying(50),
    suggestion_description character varying(300),
    priority integer,
    suggestion_description_zh character varying(300),
    suggestion_description_es character varying(300)
);


ALTER TABLE public.tab_quality_issue_suggestion OWNER TO gtmsmanager;

--
-- Name: tab_quality_reboot_task; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_quality_reboot_task (
    id integer,
    device_id character varying(60),
    is_reboot integer,
    create_time integer,
    reboot_time integer
);


ALTER TABLE public.tab_quality_reboot_task OWNER TO gtmsmanager;

--
-- Name: TABLE tab_quality_reboot_task; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON TABLE public.tab_quality_reboot_task IS '质差分析重启任务计划表';


--
-- Name: COLUMN tab_quality_reboot_task.id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_quality_reboot_task.id IS '主键';


--
-- Name: COLUMN tab_quality_reboot_task.device_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_quality_reboot_task.device_id IS '设备标识';


--
-- Name: COLUMN tab_quality_reboot_task.is_reboot; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_quality_reboot_task.is_reboot IS '是否完成重启，1：是；0：否';


--
-- Name: COLUMN tab_quality_reboot_task.create_time; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_quality_reboot_task.create_time IS '任务创建时间';


--
-- Name: COLUMN tab_quality_reboot_task.reboot_time; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_quality_reboot_task.reboot_time IS '更新时间';


--
-- Name: tab_quality_reboot_task_id_seq; Type: SEQUENCE; Schema: public; Owner: gtmsmanager
--

CREATE SEQUENCE public.tab_quality_reboot_task_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.tab_quality_reboot_task_id_seq OWNER TO gtmsmanager;

--
-- Name: tab_register_cpe_origin; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_register_cpe_origin (
    task_id integer NOT NULL,
    device_sn character varying(64) NOT NULL,
    device_ip character varying(64) DEFAULT '0'::character varying,
    device_url character varying(200),
    vendor_name character varying(64),
    model_name character varying(64),
    softwareversion character varying(64),
    hardwareversion character varying(64) DEFAULT '0'::character varying,
    add_time integer DEFAULT 0,
    update_time integer DEFAULT 0,
    status integer DEFAULT 0,
    id integer NOT NULL
);


ALTER TABLE public.tab_register_cpe_origin OWNER TO gtmsmanager;

--
-- Name: COLUMN tab_register_cpe_origin.device_ip; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_register_cpe_origin.device_ip IS 'the total of CPE file';


--
-- Name: tab_register_cpe_origin_error; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_register_cpe_origin_error (
    task_id integer NOT NULL,
    device_sn character varying(64) NOT NULL,
    reason character varying(300) NOT NULL,
    add_time integer DEFAULT 0 NOT NULL
);


ALTER TABLE public.tab_register_cpe_origin_error OWNER TO gtmsmanager;

--
-- Name: tab_register_serv_origin; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_register_serv_origin (
    task_id integer NOT NULL,
    device_sn character varying(64) NOT NULL,
    serv_type character varying(20) NOT NULL,
    serv_account character varying(64) NOT NULL,
    serv_password character varying(64) NOT NULL,
    vlan_id integer NOT NULL,
    bind_port character varying(100) NOT NULL,
    city_name character varying(200),
    wan_type integer DEFAULT 0 NOT NULL,
    speed character varying(64) NOT NULL,
    id integer NOT NULL,
    status character varying(12) DEFAULT '0'::character varying
);


ALTER TABLE public.tab_register_serv_origin OWNER TO gtmsmanager;

--
-- Name: COLUMN tab_register_serv_origin.serv_type; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_register_serv_origin.serv_type IS '22-broadband 21-iptv 14-Sip_voip 15-H248_voip';


--
-- Name: COLUMN tab_register_serv_origin.wan_type; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_register_serv_origin.wan_type IS '1-bridge 2-route';


--
-- Name: tab_register_task; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_register_task (
    task_id integer NOT NULL,
    task_name character varying(64),
    total integer DEFAULT 0 NOT NULL,
    cpe_file_name character varying(64) NOT NULL,
    serv_file_name character varying(64) NOT NULL,
    cpe_file_path character varying(200) NOT NULL,
    serv_file_path character varying(200) NOT NULL,
    create_time integer DEFAULT 0 NOT NULL,
    update_time integer DEFAULT 0 NOT NULL,
    status integer DEFAULT 0 NOT NULL,
    user_id character varying(64) NOT NULL
);


ALTER TABLE public.tab_register_task OWNER TO gtmsmanager;

--
-- Name: COLUMN tab_register_task.total; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_register_task.total IS 'the total of CPE file';


--
-- Name: tab_repair_device_info; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_repair_device_info (
    repair_vendor character varying(64) NOT NULL,
    insurance_status numeric(1,0),
    batch_number character varying(64),
    device_serialnumber character varying(64) NOT NULL,
    device_vendor character varying(64),
    device_model character varying(64),
    hardwareversion character varying(30),
    softwareversion character varying(100),
    version_check numeric(1,0),
    config_check numeric(1,0),
    serv_issue_check numeric(1,0),
    voice_regist_check numeric(1,0),
    check_result numeric(1,0),
    send_city character varying(64),
    attribution_city character varying(64),
    manufacture_date numeric(10,0),
    import_date numeric(16,0) NOT NULL
);


ALTER TABLE public.tab_repair_device_info OWNER TO gtmsmanager;

--
-- Name: tab_restartdev; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_restartdev (
    task_id numeric(14,0) NOT NULL,
    username character varying(50) NOT NULL,
    file_username character varying(50) NOT NULL,
    device_id character varying(50),
    devsn character varying(64),
    status numeric(1,0) NOT NULL,
    "time" numeric(14,0),
    res character varying(200)
);


ALTER TABLE public.tab_restartdev OWNER TO gtmsmanager;

--
-- Name: tab_restfulservice_log; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_restfulservice_log (
    request_id character varying(40),
    userinfotype numeric(1,0),
    userinfo character varying(30),
    app_id character varying(40),
    app_key character varying(40),
    province_id character varying(10),
    lan_id character varying(10),
    original_request_id character varying(40),
    req_ip character varying(20),
    req_info text,
    resp_info text,
    resp_code numeric(8,0),
    interfacename character varying(40),
    invoke_time numeric(10,0)
);


ALTER TABLE public.tab_restfulservice_log OWNER TO gtmsmanager;

--
-- Name: tab_role; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_role (
    role_id numeric(10,0) NOT NULL,
    role_name character varying(30) NOT NULL,
    role_desc text,
    role_pid numeric(10,0),
    acc_oid numeric(10,0),
    is_default numeric(65,30)
);


ALTER TABLE public.tab_role OWNER TO gtmsmanager;

--
-- Name: COLUMN tab_role.is_default; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_role.is_default IS '0为默认，1为非默认';


--
-- Name: tab_route_version; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_route_version (
    devicetype_id numeric(4,0) NOT NULL,
    add_time numeric(10,0),
    is_route numeric(2,0)
);


ALTER TABLE public.tab_route_version OWNER TO gtmsmanager;

--
-- Name: tab_rpc_match; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_rpc_match (
    tc_serial numeric(10,0) NOT NULL,
    name character varying(255) NOT NULL,
    flag numeric(1,0) NOT NULL,
    value1 character varying(255),
    value2 character varying(255),
    remark character varying(255)
);


ALTER TABLE public.tab_rpc_match OWNER TO gtmsmanager;

--
-- Name: COLUMN tab_rpc_match.flag; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_rpc_match.flag IS '-1:工单执行成功要入库的信息
0－工单执行成功要入库的信息(需求取工单参数表中数据)
1－工单执行过程中要临时保存
2工单执行过程中要临时保存的数据入库
3-1和2
';


--
-- Name: tab_seniorquery_tmp; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_seniorquery_tmp (
    filename character varying(50) NOT NULL,
    username character varying(50),
    devicesn character varying(50)
);


ALTER TABLE public.tab_seniorquery_tmp OWNER TO gtmsmanager;

--
-- Name: tab_serv_classify_statistic; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_serv_classify_statistic (
    id integer NOT NULL,
    city_id integer,
    city_name character varying(255),
    serv_type_id integer,
    serv_type_name character varying(255),
    update_time character varying(32),
    total integer,
    _no_pk_hash character varying(64)
);


ALTER TABLE public.tab_serv_classify_statistic OWNER TO gtmsmanager;

--
-- Name: tab_serv_classify_statistic_id_seq; Type: SEQUENCE; Schema: public; Owner: gtmsmanager
--

CREATE SEQUENCE public.tab_serv_classify_statistic_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.tab_serv_classify_statistic_id_seq OWNER TO gtmsmanager;

--
-- Name: tab_serv_classify_statistic_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: gtmsmanager
--

ALTER SEQUENCE public.tab_serv_classify_statistic_id_seq OWNED BY public.tab_serv_classify_statistic.id;


--
-- Name: tab_serv_template; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_serv_template (
    id bigint NOT NULL,
    name character varying(500) NOT NULL,
    vlanid character varying(10),
    serv integer,
    city_id character varying(20),
    vendor_id character varying(6),
    device_model_id character varying(4),
    devicetype_id integer,
    update_time integer NOT NULL,
    operator character varying(50),
    gw_type character varying(1),
    nserv_svlan_del integer,
    sserv_del integer,
    sserv_svlan_del integer,
    sport_del integer,
    service_id integer,
    use_type integer,
    describe character varying(1000),
    selected_keys character varying(255),
    selected_parent_keys character varying(255),
    user_id character varying(32)
);


ALTER TABLE public.tab_serv_template OWNER TO gtmsmanager;

--
-- Name: TABLE tab_serv_template; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON TABLE public.tab_serv_template IS '模板表';


--
-- Name: COLUMN tab_serv_template.id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_serv_template.id IS '模板id';


--
-- Name: COLUMN tab_serv_template.name; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_serv_template.name IS '模板名称';


--
-- Name: COLUMN tab_serv_template.serv; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_serv_template.serv IS '业务';


--
-- Name: COLUMN tab_serv_template.city_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_serv_template.city_id IS '属地id';


--
-- Name: COLUMN tab_serv_template.vendor_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_serv_template.vendor_id IS '设备厂商id';


--
-- Name: COLUMN tab_serv_template.device_model_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_serv_template.device_model_id IS '设备型号id';


--
-- Name: COLUMN tab_serv_template.devicetype_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_serv_template.devicetype_id IS '设备类型id';


--
-- Name: COLUMN tab_serv_template.update_time; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_serv_template.update_time IS '更新时间';


--
-- Name: COLUMN tab_serv_template.operator; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_serv_template.operator IS '操作者';


--
-- Name: COLUMN tab_serv_template.gw_type; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_serv_template.gw_type IS '设备类型';


--
-- Name: COLUMN tab_serv_template.service_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_serv_template.service_id IS '业务id';


--
-- Name: COLUMN tab_serv_template.use_type; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_serv_template.use_type IS '模板用途：0批量下发、1批量读取';


--
-- Name: COLUMN tab_serv_template.selected_keys; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_serv_template.selected_keys IS '选中的节点';


--
-- Name: COLUMN tab_serv_template.selected_parent_keys; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_serv_template.selected_parent_keys IS '选中的父节点';


--
-- Name: tab_serv_template_param; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_serv_template_param (
    template_id bigint NOT NULL,
    path character varying(5000) NOT NULL,
    value character varying(1000),
    type integer,
    priority integer,
    selected_key character varying(255),
    parent_key character varying(255)
);


ALTER TABLE public.tab_serv_template_param OWNER TO gtmsmanager;

--
-- Name: TABLE tab_serv_template_param; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON TABLE public.tab_serv_template_param IS '模板参数表';


--
-- Name: COLUMN tab_serv_template_param.template_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_serv_template_param.template_id IS '模板参数id';


--
-- Name: COLUMN tab_serv_template_param.path; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_serv_template_param.path IS '参数路径';


--
-- Name: COLUMN tab_serv_template_param.value; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_serv_template_param.value IS '参数值';


--
-- Name: COLUMN tab_serv_template_param.type; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_serv_template_param.type IS '参数类型';


--
-- Name: COLUMN tab_serv_template_param.priority; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_serv_template_param.priority IS '优先级';


--
-- Name: COLUMN tab_serv_template_param.selected_key; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_serv_template_param.selected_key IS '选中的节点';


--
-- Name: COLUMN tab_serv_template_param.parent_key; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_serv_template_param.parent_key IS '父节点';


--
-- Name: tab_serv_template_param_bak; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_serv_template_param_bak (
    template_id bigint NOT NULL,
    path character varying(5000) NOT NULL,
    value character varying(1000),
    type integer,
    priority integer,
    selected_key character varying(255),
    parent_key character varying(255)
);


ALTER TABLE public.tab_serv_template_param_bak OWNER TO gtmsmanager;

--
-- Name: TABLE tab_serv_template_param_bak; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON TABLE public.tab_serv_template_param_bak IS '模板参数表';


--
-- Name: COLUMN tab_serv_template_param_bak.template_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_serv_template_param_bak.template_id IS '模板参数id';


--
-- Name: COLUMN tab_serv_template_param_bak.path; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_serv_template_param_bak.path IS '参数路径';


--
-- Name: COLUMN tab_serv_template_param_bak.value; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_serv_template_param_bak.value IS '参数值';


--
-- Name: COLUMN tab_serv_template_param_bak.type; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_serv_template_param_bak.type IS '参数类型';


--
-- Name: COLUMN tab_serv_template_param_bak.priority; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_serv_template_param_bak.priority IS '优先级';


--
-- Name: COLUMN tab_serv_template_param_bak.selected_key; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_serv_template_param_bak.selected_key IS '选中的节点';


--
-- Name: COLUMN tab_serv_template_param_bak.parent_key; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_serv_template_param_bak.parent_key IS '父节点';


--
-- Name: tab_serv_template_param_bak0725; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_serv_template_param_bak0725 (
    template_id bigint NOT NULL,
    path character varying(5000) NOT NULL,
    value character varying(1000),
    type integer,
    priority integer,
    selected_key character varying(255),
    parent_key character varying(255)
);


ALTER TABLE public.tab_serv_template_param_bak0725 OWNER TO gtmsmanager;

--
-- Name: COLUMN tab_serv_template_param_bak0725.template_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_serv_template_param_bak0725.template_id IS '模板参数id';


--
-- Name: COLUMN tab_serv_template_param_bak0725.path; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_serv_template_param_bak0725.path IS '参数路径';


--
-- Name: COLUMN tab_serv_template_param_bak0725.value; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_serv_template_param_bak0725.value IS '参数值';


--
-- Name: COLUMN tab_serv_template_param_bak0725.type; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_serv_template_param_bak0725.type IS '参数类型';


--
-- Name: COLUMN tab_serv_template_param_bak0725.priority; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_serv_template_param_bak0725.priority IS '优先级';


--
-- Name: COLUMN tab_serv_template_param_bak0725.selected_key; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_serv_template_param_bak0725.selected_key IS '选中的节点';


--
-- Name: COLUMN tab_serv_template_param_bak0725.parent_key; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_serv_template_param_bak0725.parent_key IS '父节点';


--
-- Name: tab_serv_template_param_bak0729; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_serv_template_param_bak0729 (
    template_id bigint NOT NULL,
    path character varying(5000) NOT NULL,
    value character varying(1000),
    type integer,
    priority integer,
    selected_key character varying(255),
    parent_key character varying(255)
);


ALTER TABLE public.tab_serv_template_param_bak0729 OWNER TO gtmsmanager;

--
-- Name: COLUMN tab_serv_template_param_bak0729.template_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_serv_template_param_bak0729.template_id IS '模板参数id';


--
-- Name: COLUMN tab_serv_template_param_bak0729.path; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_serv_template_param_bak0729.path IS '参数路径';


--
-- Name: COLUMN tab_serv_template_param_bak0729.value; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_serv_template_param_bak0729.value IS '参数值';


--
-- Name: COLUMN tab_serv_template_param_bak0729.type; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_serv_template_param_bak0729.type IS '参数类型';


--
-- Name: COLUMN tab_serv_template_param_bak0729.priority; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_serv_template_param_bak0729.priority IS '优先级';


--
-- Name: COLUMN tab_serv_template_param_bak0729.selected_key; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_serv_template_param_bak0729.selected_key IS '选中的节点';


--
-- Name: COLUMN tab_serv_template_param_bak0729.parent_key; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_serv_template_param_bak0729.parent_key IS '父节点';


--
-- Name: tab_serv_template_param_bak0801; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_serv_template_param_bak0801 (
    template_id bigint NOT NULL,
    path character varying(5000) NOT NULL,
    value character varying(1000),
    type integer,
    priority integer,
    selected_key character varying(255),
    parent_key character varying(255)
);


ALTER TABLE public.tab_serv_template_param_bak0801 OWNER TO gtmsmanager;

--
-- Name: COLUMN tab_serv_template_param_bak0801.template_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_serv_template_param_bak0801.template_id IS '模板参数id';


--
-- Name: COLUMN tab_serv_template_param_bak0801.path; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_serv_template_param_bak0801.path IS '参数路径';


--
-- Name: COLUMN tab_serv_template_param_bak0801.value; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_serv_template_param_bak0801.value IS '参数值';


--
-- Name: COLUMN tab_serv_template_param_bak0801.type; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_serv_template_param_bak0801.type IS '参数类型';


--
-- Name: COLUMN tab_serv_template_param_bak0801.priority; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_serv_template_param_bak0801.priority IS '优先级';


--
-- Name: COLUMN tab_serv_template_param_bak0801.selected_key; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_serv_template_param_bak0801.selected_key IS '选中的节点';


--
-- Name: COLUMN tab_serv_template_param_bak0801.parent_key; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_serv_template_param_bak0801.parent_key IS '父节点';


--
-- Name: tab_serv_template_param_bak0802; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_serv_template_param_bak0802 (
    template_id bigint NOT NULL,
    path character varying(5000) NOT NULL,
    value character varying(1000),
    type integer,
    priority integer,
    selected_key character varying(255),
    parent_key character varying(255)
);


ALTER TABLE public.tab_serv_template_param_bak0802 OWNER TO gtmsmanager;

--
-- Name: COLUMN tab_serv_template_param_bak0802.template_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_serv_template_param_bak0802.template_id IS '模板参数id';


--
-- Name: COLUMN tab_serv_template_param_bak0802.path; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_serv_template_param_bak0802.path IS '参数路径';


--
-- Name: COLUMN tab_serv_template_param_bak0802.value; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_serv_template_param_bak0802.value IS '参数值';


--
-- Name: COLUMN tab_serv_template_param_bak0802.type; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_serv_template_param_bak0802.type IS '参数类型';


--
-- Name: COLUMN tab_serv_template_param_bak0802.priority; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_serv_template_param_bak0802.priority IS '优先级';


--
-- Name: COLUMN tab_serv_template_param_bak0802.selected_key; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_serv_template_param_bak0802.selected_key IS '选中的节点';


--
-- Name: COLUMN tab_serv_template_param_bak0802.parent_key; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_serv_template_param_bak0802.parent_key IS '父节点';


--
-- Name: tab_serv_template_param_bak0803; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_serv_template_param_bak0803 (
    template_id bigint NOT NULL,
    path character varying(5000) NOT NULL,
    value character varying(1000),
    type integer,
    priority integer,
    selected_key character varying(255),
    parent_key character varying(255)
);


ALTER TABLE public.tab_serv_template_param_bak0803 OWNER TO gtmsmanager;

--
-- Name: COLUMN tab_serv_template_param_bak0803.template_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_serv_template_param_bak0803.template_id IS '模板参数id';


--
-- Name: COLUMN tab_serv_template_param_bak0803.path; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_serv_template_param_bak0803.path IS '参数路径';


--
-- Name: COLUMN tab_serv_template_param_bak0803.value; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_serv_template_param_bak0803.value IS '参数值';


--
-- Name: COLUMN tab_serv_template_param_bak0803.type; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_serv_template_param_bak0803.type IS '参数类型';


--
-- Name: COLUMN tab_serv_template_param_bak0803.priority; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_serv_template_param_bak0803.priority IS '优先级';


--
-- Name: COLUMN tab_serv_template_param_bak0803.selected_key; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_serv_template_param_bak0803.selected_key IS '选中的节点';


--
-- Name: COLUMN tab_serv_template_param_bak0803.parent_key; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_serv_template_param_bak0803.parent_key IS '父节点';


--
-- Name: tab_serv_template_param_bak0813; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_serv_template_param_bak0813 (
    template_id bigint NOT NULL,
    path character varying(5000) NOT NULL,
    value character varying(1000),
    type integer,
    priority integer,
    selected_key character varying(255),
    parent_key character varying(255)
);


ALTER TABLE public.tab_serv_template_param_bak0813 OWNER TO gtmsmanager;

--
-- Name: COLUMN tab_serv_template_param_bak0813.template_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_serv_template_param_bak0813.template_id IS '模板参数id';


--
-- Name: COLUMN tab_serv_template_param_bak0813.path; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_serv_template_param_bak0813.path IS '参数路径';


--
-- Name: COLUMN tab_serv_template_param_bak0813.value; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_serv_template_param_bak0813.value IS '参数值';


--
-- Name: COLUMN tab_serv_template_param_bak0813.type; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_serv_template_param_bak0813.type IS '参数类型';


--
-- Name: COLUMN tab_serv_template_param_bak0813.priority; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_serv_template_param_bak0813.priority IS '优先级';


--
-- Name: COLUMN tab_serv_template_param_bak0813.selected_key; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_serv_template_param_bak0813.selected_key IS '选中的节点';


--
-- Name: COLUMN tab_serv_template_param_bak0813.parent_key; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_serv_template_param_bak0813.parent_key IS '父节点';


--
-- Name: tab_serv_template_param_bak081302; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_serv_template_param_bak081302 (
    template_id bigint NOT NULL,
    path character varying(5000) NOT NULL,
    value character varying(1000),
    type integer,
    priority integer,
    selected_key character varying(255),
    parent_key character varying(255)
);


ALTER TABLE public.tab_serv_template_param_bak081302 OWNER TO gtmsmanager;

--
-- Name: COLUMN tab_serv_template_param_bak081302.template_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_serv_template_param_bak081302.template_id IS '模板参数id';


--
-- Name: COLUMN tab_serv_template_param_bak081302.path; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_serv_template_param_bak081302.path IS '参数路径';


--
-- Name: COLUMN tab_serv_template_param_bak081302.value; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_serv_template_param_bak081302.value IS '参数值';


--
-- Name: COLUMN tab_serv_template_param_bak081302.type; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_serv_template_param_bak081302.type IS '参数类型';


--
-- Name: COLUMN tab_serv_template_param_bak081302.priority; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_serv_template_param_bak081302.priority IS '优先级';


--
-- Name: COLUMN tab_serv_template_param_bak081302.selected_key; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_serv_template_param_bak081302.selected_key IS '选中的节点';


--
-- Name: COLUMN tab_serv_template_param_bak081302.parent_key; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_serv_template_param_bak081302.parent_key IS '父节点';


--
-- Name: tab_serv_template_param_bak0902; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_serv_template_param_bak0902 (
    template_id bigint NOT NULL,
    path character varying(5000) NOT NULL,
    value character varying(1000),
    type integer,
    priority integer,
    selected_key character varying(255),
    parent_key character varying(255)
);


ALTER TABLE public.tab_serv_template_param_bak0902 OWNER TO gtmsmanager;

--
-- Name: COLUMN tab_serv_template_param_bak0902.template_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_serv_template_param_bak0902.template_id IS '模板参数id';


--
-- Name: COLUMN tab_serv_template_param_bak0902.path; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_serv_template_param_bak0902.path IS '参数路径';


--
-- Name: COLUMN tab_serv_template_param_bak0902.value; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_serv_template_param_bak0902.value IS '参数值';


--
-- Name: COLUMN tab_serv_template_param_bak0902.type; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_serv_template_param_bak0902.type IS '参数类型';


--
-- Name: COLUMN tab_serv_template_param_bak0902.priority; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_serv_template_param_bak0902.priority IS '优先级';


--
-- Name: COLUMN tab_serv_template_param_bak0902.selected_key; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_serv_template_param_bak0902.selected_key IS '选中的节点';


--
-- Name: COLUMN tab_serv_template_param_bak0902.parent_key; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_serv_template_param_bak0902.parent_key IS '父节点';


--
-- Name: tab_serv_template_param_bak0909; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_serv_template_param_bak0909 (
    template_id bigint NOT NULL,
    path character varying(5000) NOT NULL,
    value character varying(1000),
    type integer,
    priority integer,
    selected_key character varying(255),
    parent_key character varying(255)
);


ALTER TABLE public.tab_serv_template_param_bak0909 OWNER TO gtmsmanager;

--
-- Name: COLUMN tab_serv_template_param_bak0909.template_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_serv_template_param_bak0909.template_id IS '模板参数id';


--
-- Name: COLUMN tab_serv_template_param_bak0909.path; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_serv_template_param_bak0909.path IS '参数路径';


--
-- Name: COLUMN tab_serv_template_param_bak0909.value; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_serv_template_param_bak0909.value IS '参数值';


--
-- Name: COLUMN tab_serv_template_param_bak0909.type; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_serv_template_param_bak0909.type IS '参数类型';


--
-- Name: COLUMN tab_serv_template_param_bak0909.priority; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_serv_template_param_bak0909.priority IS '优先级';


--
-- Name: COLUMN tab_serv_template_param_bak0909.selected_key; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_serv_template_param_bak0909.selected_key IS '选中的节点';


--
-- Name: COLUMN tab_serv_template_param_bak0909.parent_key; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_serv_template_param_bak0909.parent_key IS '父节点';


--
-- Name: tab_service; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_service (
    service_id numeric(4,0) NOT NULL,
    serv_type_id numeric(4,0) DEFAULT 0 NOT NULL,
    oper_type_id numeric(4,0) DEFAULT 0 NOT NULL,
    wan_type numeric(2,0) DEFAULT '-1'::integer NOT NULL,
    flag numeric(1,0) DEFAULT '-1'::integer NOT NULL,
    service_name character varying(50),
    service_desc character varying(200)
);


ALTER TABLE public.tab_service OWNER TO gtmsmanager;

--
-- Name: COLUMN tab_service.wan_type; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_service.wan_type IS '-1:默认，1：桥接，2：路由';


--
-- Name: COLUMN tab_service.flag; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_service.flag IS '-1: 用户新增业务，0:系统维护业务，1:家庭网关业务，2：企业网关业务';


--
-- Name: tab_service_sub; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_service_sub (
    service_id numeric(4,0),
    wan_type numeric(2,0),
    sub_service_id numeric(4,0) NOT NULL,
    service_desc numeric(2,0),
    access_type numeric(2,0)
);


ALTER TABLE public.tab_service_sub OWNER TO gtmsmanager;

--
-- Name: COLUMN tab_service_sub.wan_type; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_service_sub.wan_type IS '-1:默认
1：桥接
2：路由
';


--
-- Name: COLUMN tab_service_sub.service_desc; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_service_sub.service_desc IS '0：其他业务
1：IPTV
2：IPTVS
该字段对于iptv业务有用 其他业务暂时没有用
';


--
-- Name: tab_servicecode; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_servicecode (
    servicecode character varying(100) NOT NULL,
    service_id numeric(4,0),
    template_id numeric(10,0),
    devicetype_id numeric(4,0),
    citylist character varying(255)
);


ALTER TABLE public.tab_servicecode OWNER TO gtmsmanager;

--
-- Name: tab_setmulticast_dev; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_setmulticast_dev (
    device_id character varying(10) NOT NULL,
    device_serialnumber character varying(64),
    iptv_account character varying(20),
    status numeric(6,0) NOT NULL,
    settime numeric(10,0),
    city_id character varying(20) NOT NULL
);


ALTER TABLE public.tab_setmulticast_dev OWNER TO gtmsmanager;

--
-- Name: tab_setmulticast_task; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_setmulticast_task (
    task_id numeric(10,0) NOT NULL,
    task_name character varying(100) NOT NULL,
    acc_oid numeric(14,0) NOT NULL,
    add_time numeric(10,0) NOT NULL,
    service_id numeric(4,0) NOT NULL,
    strategy_type numeric(2,0),
    param text,
    type numeric(1,0) NOT NULL,
    status numeric(1,0) NOT NULL
);


ALTER TABLE public.tab_setmulticast_task OWNER TO gtmsmanager;

--
-- Name: tab_setmulticast_task_dev; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_setmulticast_task_dev (
    task_id numeric(10,0) NOT NULL,
    file_username character varying(64) NOT NULL,
    device_id character varying(10),
    device_serialnumber character varying(64),
    city_id character varying(64),
    result_id numeric(10,0),
    status numeric(3,0),
    add_time numeric(10,0) NOT NULL,
    update_time numeric(10,0) NOT NULL,
    res character varying(200)
);


ALTER TABLE public.tab_setmulticast_task_dev OWNER TO gtmsmanager;

--
-- Name: tab_sheet; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_sheet (
    sheet_id character varying(50) NOT NULL,
    device_id character varying(50),
    service_id numeric(10,0) NOT NULL,
    sheet_source numeric(2,0) NOT NULL,
    prot_id numeric(1,0) NOT NULL,
    acc_oid numeric(10,0),
    sheet_type numeric(1,0) NOT NULL
);


ALTER TABLE public.tab_sheet OWNER TO gtmsmanager;

--
-- Name: COLUMN tab_sheet.sheet_source; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_sheet.sheet_source IS '0－WEB
1—  bss
2—  ftp
3—  ACS
4—  ScheduleJob
10--其它
';


--
-- Name: COLUMN tab_sheet.prot_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_sheet.prot_id IS '1:TR069
2:SNMP
';


--
-- Name: COLUMN tab_sheet.sheet_type; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_sheet.sheet_type IS '1：老工单
2：新工单';


--
-- Name: tab_sheet_auth; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_sheet_auth (
    auth_id numeric(10,0) NOT NULL,
    auth_user character varying(25) NOT NULL,
    auth_pwd character varying(25) NOT NULL,
    acc_id numeric(2,0) NOT NULL,
    add_time numeric(10,0),
    status numeric(2,0) NOT NULL
);


ALTER TABLE public.tab_sheet_auth OWNER TO gtmsmanager;

--
-- Name: COLUMN tab_sheet_auth.status; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_sheet_auth.status IS '1:����  0������';


--
-- Name: tab_sheet_cmd; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_sheet_cmd (
    sheet_id character varying(50) NOT NULL,
    rpc_id numeric(10,0) NOT NULL,
    rpc_order numeric(10,0) NOT NULL,
    is_save numeric(10,0) NOT NULL,
    tc_serial integer
);


ALTER TABLE public.tab_sheet_cmd OWNER TO gtmsmanager;

--
-- Name: tab_sheet_para; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_sheet_para (
    sheet_id character varying(50) NOT NULL,
    tc_serial numeric(10,0),
    para_serial numeric(10,0) NOT NULL,
    def_value text,
    para_type_id numeric(10,0),
    rpc_order numeric(10,0) NOT NULL
);


ALTER TABLE public.tab_sheet_para OWNER TO gtmsmanager;

--
-- Name: tab_sheet_para_value; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_sheet_para_value (
    strategy_id bigint NOT NULL,
    order_id bigint NOT NULL,
    para_value character varying(4000),
    id bigint NOT NULL
);


ALTER TABLE public.tab_sheet_para_value OWNER TO gtmsmanager;

--
-- Name: tab_sheet_report; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_sheet_report (
    sheet_id character varying(50) NOT NULL,
    gather_id character varying(30) NOT NULL,
    city_id character varying(20) NOT NULL,
    device_id character varying(50) NOT NULL,
    username character varying(40),
    service_id smallint NOT NULL,
    exec_status smallint DEFAULT 0 NOT NULL,
    exec_desc character varying(1000),
    exec_count smallint DEFAULT 1 NOT NULL,
    fault_code bigint,
    fault_desc character varying(1000),
    receive_time bigint NOT NULL,
    start_time bigint,
    end_time bigint,
    acc_oid bigint DEFAULT 1
);


ALTER TABLE public.tab_sheet_report OWNER TO gtmsmanager;

--
-- Name: tab_sip_info; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_sip_info (
    sip_id numeric(5,0) NOT NULL,
    prox_serv character varying(50),
    prox_port numeric(5,0),
    stand_prox_serv character varying(50),
    stand_prox_port numeric(5,0),
    regi_serv character varying(50),
    regi_port numeric(5,0),
    stand_regi_serv character varying(50),
    stand_regi_port numeric(5,0),
    out_bound_proxy character varying(50),
    out_bound_port numeric(5,0),
    stand_out_bound_proxy character varying(50),
    stand_out_bound_port numeric(5,0),
    remark character varying(100),
    prox_transport character varying(10),
    stand_prox_transport character varying(10),
    regi_transport character varying(10),
    stand_regi_transport character varying(10)
);


ALTER TABLE public.tab_sip_info OWNER TO gtmsmanager;

--
-- Name: tab_soft_upgrade_record; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_soft_upgrade_record (
    record_id numeric(10,0) NOT NULL,
    vendor_id character varying(6) NOT NULL,
    device_model_id character varying(4) NOT NULL,
    current_devicetype_id numeric(4,0) NOT NULL,
    target_devicetype character varying(20) NOT NULL,
    upgrade_range character varying(80) NOT NULL,
    device_count numeric(10,0),
    upgrade_reason text,
    upgrade_method character varying(80) NOT NULL,
    upgrade_start_time numeric(10,0) NOT NULL,
    upgrade_end_time numeric(10,0) NOT NULL,
    contact_way character varying(80),
    upgrade_file_name character varying(80)
);


ALTER TABLE public.tab_soft_upgrade_record OWNER TO gtmsmanager;

--
-- Name: tab_software_file; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_software_file (
    softwarefile_id bigint NOT NULL,
    softwarefile_name character varying(100) NOT NULL,
    softwarefile_description character varying(200),
    softwarefile_size numeric(10,0),
    dir_id numeric(10,0),
    softwarefile_status numeric(1,0),
    softwarefile_isexist numeric(1,0),
    devicetype_id numeric(10,0) NOT NULL,
    citylist character varying(255),
    servicelist character varying(255),
    device_model_id character varying(4)
);


ALTER TABLE public.tab_software_file OWNER TO gtmsmanager;

--
-- Name: tab_software_file_softwarefile_id_seq; Type: SEQUENCE; Schema: public; Owner: gtmsmanager
--

ALTER TABLE public.tab_software_file ALTER COLUMN softwarefile_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.tab_software_file_softwarefile_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: tab_softwareup_tmp; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_softwareup_tmp (
    data character varying(64),
    type numeric(1,0)
);


ALTER TABLE public.tab_softwareup_tmp OWNER TO gtmsmanager;

--
-- Name: tab_speed_dev_rate; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_speed_dev_rate (
    user_id numeric(10,0) NOT NULL,
    serv_type_id numeric(4,0) NOT NULL,
    device_serialnumber character varying(64) NOT NULL,
    pppoe_name character varying(40) NOT NULL,
    account_suffix character varying(10),
    rate numeric(10,0) NOT NULL,
    add_time numeric(10,0) NOT NULL,
    city_id character varying(20) NOT NULL,
    parent_id character varying(20) NOT NULL
);


ALTER TABLE public.tab_speed_dev_rate OWNER TO gtmsmanager;

--
-- Name: tab_speed_net; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_speed_net (
    test_rate numeric(10,0) NOT NULL,
    city_id character varying(20) NOT NULL,
    net_account character varying(100) NOT NULL,
    net_password character varying(50) NOT NULL
);


ALTER TABLE public.tab_speed_net OWNER TO gtmsmanager;

--
-- Name: tab_speed_param; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_speed_param (
    city_id character varying(20) NOT NULL,
    test_url character varying(80) NOT NULL
);


ALTER TABLE public.tab_speed_param OWNER TO gtmsmanager;

--
-- Name: tab_stack_task; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_stack_task (
    task_id numeric(10,0) NOT NULL,
    acc_oid numeric(14,0) NOT NULL,
    add_time numeric(10,0) NOT NULL,
    service_id numeric(4,0) NOT NULL,
    strategy_type numeric(2,0),
    param text,
    type numeric(1,0) NOT NULL,
    status numeric(1,0) NOT NULL
);


ALTER TABLE public.tab_stack_task OWNER TO gtmsmanager;

--
-- Name: tab_stack_task_dev; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_stack_task_dev (
    task_id numeric(10,0) NOT NULL,
    file_username character varying(64) NOT NULL,
    loid character varying(64),
    netusername character varying(64),
    device_id character varying(10),
    device_serialnumber character varying(64),
    oui character varying(6),
    result_id numeric(10,0),
    status numeric(3,0),
    add_time numeric(10,0) NOT NULL,
    update_time numeric(10,0) NOT NULL,
    res character varying(200)
);


ALTER TABLE public.tab_stack_task_dev OWNER TO gtmsmanager;

--
-- Name: tab_static_src; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_static_src (
    src_type numeric(10,0) NOT NULL,
    src_code character varying(5) NOT NULL,
    src_key character varying(50) NOT NULL,
    src_value character varying(50) NOT NULL,
    src_desc character varying(200)
);


ALTER TABLE public.tab_static_src OWNER TO gtmsmanager;

--
-- Name: COLUMN tab_static_src.src_key; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_static_src.src_key IS '0:success
1:system fault
2:server fault
3:client fault
4:other fault
';


--
-- Name: tab_sub_bind_log; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_sub_bind_log (
    bind_id numeric(15,0) NOT NULL,
    username character varying(40) NOT NULL,
    credno character varying(20),
    device_id character varying(50) NOT NULL,
    binddate numeric(10,0) NOT NULL,
    bind_status numeric(2,0),
    bind_result numeric(2,0) NOT NULL,
    bind_desc character varying(50),
    userline numeric(6,0) NOT NULL,
    remark character varying(100),
    oper_type numeric(1,0),
    bind_type numeric(1,0),
    dealstaff character varying(80) NOT NULL
);


ALTER TABLE public.tab_sub_bind_log OWNER TO gtmsmanager;

--
-- Name: tab_summary_data; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_summary_data (
    deviceid character varying(50) NOT NULL,
    productclass character varying(50),
    registstatus character varying(50),
    cityname character varying(50),
    registtime character varying(50),
    sysuptime character varying(50),
    lastmodifytime_date character varying(50),
    hgtype character varying(50),
    changjia character varying(50),
    softver character varying(50),
    name character varying(50),
    ippprotocol character varying(50),
    publicip character varying(50),
    ext3 character varying(50),
    userid character varying(50),
    speed character varying(50),
    uptype character varying(50),
    device_id character varying(50) NOT NULL,
    device_sn character varying(255)
);


ALTER TABLE public.tab_summary_data OWNER TO gtmsmanager;

--
-- Name: tab_template; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_template (
    template_id numeric(10,0) NOT NULL,
    template_name character varying(255),
    devicetype_id numeric(6,0) NOT NULL,
    template_desc character varying(255),
    is_save numeric(1,0) NOT NULL
);


ALTER TABLE public.tab_template OWNER TO gtmsmanager;

--
-- Name: tab_template_cmd; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_template_cmd (
    tc_serial numeric(10,0) NOT NULL,
    template_id numeric(10,0) NOT NULL,
    rpc_id numeric(10,0) NOT NULL,
    rpc_order numeric(10,0) NOT NULL,
    is_save numeric(10,0) NOT NULL
);


ALTER TABLE public.tab_template_cmd OWNER TO gtmsmanager;

--
-- Name: COLUMN tab_template_cmd.is_save; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_template_cmd.is_save IS '1:要
0：不要
';


--
-- Name: tab_template_cmd_para; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_template_cmd_para (
    tc_serial numeric(10,0) NOT NULL,
    para_serial numeric(10,0) NOT NULL,
    para_id numeric(10,0),
    have_defvalue numeric(1,0),
    have_parent_para numeric(1,0),
    def_value text,
    p_para_serial numeric(10,0),
    rpc_order numeric(10,0),
    para_type_id numeric(10,0)
);


ALTER TABLE public.tab_template_cmd_para OWNER TO gtmsmanager;

--
-- Name: tab_temporary_device; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_temporary_device (
    filename character varying(150) NOT NULL,
    device_serialnumber character varying(100) NOT NULL
);


ALTER TABLE public.tab_temporary_device OWNER TO gtmsmanager;

--
-- Name: tab_tree_item; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_tree_item (
    sequence numeric(6,0),
    tree_id character varying(36) NOT NULL,
    item_id character varying(36) NOT NULL
);


ALTER TABLE public.tab_tree_item OWNER TO gtmsmanager;

--
-- Name: tab_tree_role; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_tree_role (
    sequence numeric(6,0),
    tree_id character varying(36) NOT NULL,
    role_id numeric(65,30) NOT NULL
);


ALTER TABLE public.tab_tree_role OWNER TO gtmsmanager;

--
-- Name: tab_tt_alarm; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_tt_alarm (
    device_id character varying(50) DEFAULT '0'::character varying NOT NULL,
    device_serialnumber character varying(40),
    add_time character varying(50) DEFAULT '0'::character varying NOT NULL
);


ALTER TABLE public.tab_tt_alarm OWNER TO gtmsmanager;

--
-- Name: tab_tt_alarm_fail; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_tt_alarm_fail (
    id integer NOT NULL,
    device_id character varying(50) NOT NULL,
    api_result_code character varying(50) DEFAULT '0'::character varying,
    api_result_desc character varying(200),
    api_method character varying(200),
    add_time character varying(50) DEFAULT '0'::character varying NOT NULL
);


ALTER TABLE public.tab_tt_alarm_fail OWNER TO gtmsmanager;

--
-- Name: tab_upload_log_file_info; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_upload_log_file_info (
    device_id integer NOT NULL,
    file_name character varying(255) NOT NULL,
    create_time timestamp without time zone,
    status smallint DEFAULT 0 NOT NULL
);


ALTER TABLE public.tab_upload_log_file_info OWNER TO gtmsmanager;

--
-- Name: tab_ux_inform_log_bak_20260324121914; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_ux_inform_log_bak_20260324121914 (
    id bigint NOT NULL,
    serial_number character varying(128),
    device_type character varying(32),
    sync_type smallint,
    oui character varying(32),
    product_class character varying(128),
    manufacturer character varying(128),
    success smallint NOT NULL,
    error_msg character varying(1024),
    create_time bigint NOT NULL
);


ALTER TABLE public.tab_ux_inform_log_bak_20260324121914 OWNER TO gtmsmanager;

--
-- Name: TABLE tab_ux_inform_log_bak_20260324121914; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON TABLE public.tab_ux_inform_log_bak_20260324121914 IS 'UX Inform 同步日志';


--
-- Name: COLUMN tab_ux_inform_log_bak_20260324121914.serial_number; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_ux_inform_log_bak_20260324121914.serial_number IS '设备序列号（DeviceId.SerialNumber）';


--
-- Name: COLUMN tab_ux_inform_log_bak_20260324121914.device_type; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_ux_inform_log_bak_20260324121914.device_type IS '设备类型（ONT/AP/STB）';


--
-- Name: COLUMN tab_ux_inform_log_bak_20260324121914.sync_type; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_ux_inform_log_bak_20260324121914.sync_type IS '同步类型：0-普通上报，1-IP变更';


--
-- Name: COLUMN tab_ux_inform_log_bak_20260324121914.oui; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_ux_inform_log_bak_20260324121914.oui IS '厂商OUI（DeviceId.OUI）';


--
-- Name: COLUMN tab_ux_inform_log_bak_20260324121914.product_class; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_ux_inform_log_bak_20260324121914.product_class IS '产品型号（DeviceId.ProductClass）';


--
-- Name: COLUMN tab_ux_inform_log_bak_20260324121914.manufacturer; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_ux_inform_log_bak_20260324121914.manufacturer IS '厂商名称（DeviceId.Manufacturer）';


--
-- Name: COLUMN tab_ux_inform_log_bak_20260324121914.success; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_ux_inform_log_bak_20260324121914.success IS '是否成功：1-成功，0-失败';


--
-- Name: COLUMN tab_ux_inform_log_bak_20260324121914.error_msg; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_ux_inform_log_bak_20260324121914.error_msg IS '失败时的错误信息';


--
-- Name: COLUMN tab_ux_inform_log_bak_20260324121914.create_time; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_ux_inform_log_bak_20260324121914.create_time IS '记录时间（秒级时间戳）';


--
-- Name: tab_ux_inform_log_id_seq; Type: SEQUENCE; Schema: public; Owner: gtmsmanager
--

CREATE SEQUENCE public.tab_ux_inform_log_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.tab_ux_inform_log_id_seq OWNER TO gtmsmanager;

--
-- Name: tab_ux_inform_log_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: gtmsmanager
--

ALTER SEQUENCE public.tab_ux_inform_log_id_seq OWNED BY public.tab_ux_inform_log_bak_20260324121914.id;


--
-- Name: tab_ux_inform_log; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_ux_inform_log (
    id bigint DEFAULT nextval('public.tab_ux_inform_log_id_seq'::regclass) NOT NULL,
    serial_number character varying(128),
    device_type character varying(32),
    sync_type smallint,
    oui character varying(32),
    product_class character varying(128),
    manufacturer character varying(128),
    success smallint NOT NULL,
    error_msg character varying(1024),
    create_time bigint NOT NULL
)
PARTITION BY RANGE (create_time);


ALTER TABLE public.tab_ux_inform_log OWNER TO gtmsmanager;

--
-- Name: TABLE tab_ux_inform_log; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON TABLE public.tab_ux_inform_log IS 'UX Inform 同步日志';


--
-- Name: COLUMN tab_ux_inform_log.serial_number; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_ux_inform_log.serial_number IS '设备序列号（DeviceId.SerialNumber）';


--
-- Name: COLUMN tab_ux_inform_log.device_type; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_ux_inform_log.device_type IS '设备类型（ONT/AP/STB）';


--
-- Name: COLUMN tab_ux_inform_log.sync_type; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_ux_inform_log.sync_type IS '同步类型：0-普通上报，1-IP变更';


--
-- Name: COLUMN tab_ux_inform_log.oui; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_ux_inform_log.oui IS '厂商OUI（DeviceId.OUI）';


--
-- Name: COLUMN tab_ux_inform_log.product_class; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_ux_inform_log.product_class IS '产品型号（DeviceId.ProductClass）';


--
-- Name: COLUMN tab_ux_inform_log.manufacturer; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_ux_inform_log.manufacturer IS '厂商名称（DeviceId.Manufacturer）';


--
-- Name: COLUMN tab_ux_inform_log.success; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_ux_inform_log.success IS '是否成功：1-成功，0-失败';


--
-- Name: COLUMN tab_ux_inform_log.error_msg; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_ux_inform_log.error_msg IS '失败时的错误信息';


--
-- Name: COLUMN tab_ux_inform_log.create_time; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_ux_inform_log.create_time IS '记录时间（秒级时间戳）';


--
-- Name: tab_ux_inform_log_default; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_ux_inform_log_default (
    id bigint DEFAULT nextval('public.tab_ux_inform_log_id_seq'::regclass) NOT NULL,
    serial_number character varying(128),
    device_type character varying(32),
    sync_type smallint,
    oui character varying(32),
    product_class character varying(128),
    manufacturer character varying(128),
    success smallint NOT NULL,
    error_msg character varying(1024),
    create_time bigint NOT NULL
);


ALTER TABLE public.tab_ux_inform_log_default OWNER TO gtmsmanager;

--
-- Name: tab_ux_inform_log_p20260323; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_ux_inform_log_p20260323 (
    id bigint DEFAULT nextval('public.tab_ux_inform_log_id_seq'::regclass) NOT NULL,
    serial_number character varying(128),
    device_type character varying(32),
    sync_type smallint,
    oui character varying(32),
    product_class character varying(128),
    manufacturer character varying(128),
    success smallint NOT NULL,
    error_msg character varying(1024),
    create_time bigint NOT NULL
);


ALTER TABLE public.tab_ux_inform_log_p20260323 OWNER TO gtmsmanager;

--
-- Name: tab_ux_inform_log_p20260324; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_ux_inform_log_p20260324 (
    id bigint DEFAULT nextval('public.tab_ux_inform_log_id_seq'::regclass) NOT NULL,
    serial_number character varying(128),
    device_type character varying(32),
    sync_type smallint,
    oui character varying(32),
    product_class character varying(128),
    manufacturer character varying(128),
    success smallint NOT NULL,
    error_msg character varying(1024),
    create_time bigint NOT NULL
);


ALTER TABLE public.tab_ux_inform_log_p20260324 OWNER TO gtmsmanager;

--
-- Name: tab_ux_inform_log_p20260325; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_ux_inform_log_p20260325 (
    id bigint DEFAULT nextval('public.tab_ux_inform_log_id_seq'::regclass) NOT NULL,
    serial_number character varying(128),
    device_type character varying(32),
    sync_type smallint,
    oui character varying(32),
    product_class character varying(128),
    manufacturer character varying(128),
    success smallint NOT NULL,
    error_msg character varying(1024),
    create_time bigint NOT NULL
);


ALTER TABLE public.tab_ux_inform_log_p20260325 OWNER TO gtmsmanager;

--
-- Name: tab_ux_inform_log_p20260326; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_ux_inform_log_p20260326 (
    id bigint DEFAULT nextval('public.tab_ux_inform_log_id_seq'::regclass) NOT NULL,
    serial_number character varying(128),
    device_type character varying(32),
    sync_type smallint,
    oui character varying(32),
    product_class character varying(128),
    manufacturer character varying(128),
    success smallint NOT NULL,
    error_msg character varying(1024),
    create_time bigint NOT NULL
);


ALTER TABLE public.tab_ux_inform_log_p20260326 OWNER TO gtmsmanager;

--
-- Name: tab_ux_inform_log_p20260327; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_ux_inform_log_p20260327 (
    id bigint DEFAULT nextval('public.tab_ux_inform_log_id_seq'::regclass) NOT NULL,
    serial_number character varying(128),
    device_type character varying(32),
    sync_type smallint,
    oui character varying(32),
    product_class character varying(128),
    manufacturer character varying(128),
    success smallint NOT NULL,
    error_msg character varying(1024),
    create_time bigint NOT NULL
);


ALTER TABLE public.tab_ux_inform_log_p20260327 OWNER TO gtmsmanager;

--
-- Name: tab_ux_inform_log_p20260328; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_ux_inform_log_p20260328 (
    id bigint DEFAULT nextval('public.tab_ux_inform_log_id_seq'::regclass) NOT NULL,
    serial_number character varying(128),
    device_type character varying(32),
    sync_type smallint,
    oui character varying(32),
    product_class character varying(128),
    manufacturer character varying(128),
    success smallint NOT NULL,
    error_msg character varying(1024),
    create_time bigint NOT NULL
);


ALTER TABLE public.tab_ux_inform_log_p20260328 OWNER TO gtmsmanager;

--
-- Name: tab_ux_inform_log_p20260329; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_ux_inform_log_p20260329 (
    id bigint DEFAULT nextval('public.tab_ux_inform_log_id_seq'::regclass) NOT NULL,
    serial_number character varying(128),
    device_type character varying(32),
    sync_type smallint,
    oui character varying(32),
    product_class character varying(128),
    manufacturer character varying(128),
    success smallint NOT NULL,
    error_msg character varying(1024),
    create_time bigint NOT NULL
);


ALTER TABLE public.tab_ux_inform_log_p20260329 OWNER TO gtmsmanager;

--
-- Name: tab_ux_inform_log_p20260330; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_ux_inform_log_p20260330 (
    id bigint DEFAULT nextval('public.tab_ux_inform_log_id_seq'::regclass) NOT NULL,
    serial_number character varying(128),
    device_type character varying(32),
    sync_type smallint,
    oui character varying(32),
    product_class character varying(128),
    manufacturer character varying(128),
    success smallint NOT NULL,
    error_msg character varying(1024),
    create_time bigint NOT NULL
);


ALTER TABLE public.tab_ux_inform_log_p20260330 OWNER TO gtmsmanager;

--
-- Name: tab_ux_inform_log_p20260331; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_ux_inform_log_p20260331 (
    id bigint DEFAULT nextval('public.tab_ux_inform_log_id_seq'::regclass) NOT NULL,
    serial_number character varying(128),
    device_type character varying(32),
    sync_type smallint,
    oui character varying(32),
    product_class character varying(128),
    manufacturer character varying(128),
    success smallint NOT NULL,
    error_msg character varying(1024),
    create_time bigint NOT NULL
);


ALTER TABLE public.tab_ux_inform_log_p20260331 OWNER TO gtmsmanager;

--
-- Name: tab_ux_inform_log_p20260401; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_ux_inform_log_p20260401 (
    id bigint DEFAULT nextval('public.tab_ux_inform_log_id_seq'::regclass) NOT NULL,
    serial_number character varying(128),
    device_type character varying(32),
    sync_type smallint,
    oui character varying(32),
    product_class character varying(128),
    manufacturer character varying(128),
    success smallint NOT NULL,
    error_msg character varying(1024),
    create_time bigint NOT NULL
);


ALTER TABLE public.tab_ux_inform_log_p20260401 OWNER TO gtmsmanager;

--
-- Name: tab_ux_inform_log_p20260402; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_ux_inform_log_p20260402 (
    id bigint DEFAULT nextval('public.tab_ux_inform_log_id_seq'::regclass) NOT NULL,
    serial_number character varying(128),
    device_type character varying(32),
    sync_type smallint,
    oui character varying(32),
    product_class character varying(128),
    manufacturer character varying(128),
    success smallint NOT NULL,
    error_msg character varying(1024),
    create_time bigint NOT NULL
);


ALTER TABLE public.tab_ux_inform_log_p20260402 OWNER TO gtmsmanager;

--
-- Name: tab_ux_inform_log_p20260403; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_ux_inform_log_p20260403 (
    id bigint DEFAULT nextval('public.tab_ux_inform_log_id_seq'::regclass) NOT NULL,
    serial_number character varying(128),
    device_type character varying(32),
    sync_type smallint,
    oui character varying(32),
    product_class character varying(128),
    manufacturer character varying(128),
    success smallint NOT NULL,
    error_msg character varying(1024),
    create_time bigint NOT NULL
);


ALTER TABLE public.tab_ux_inform_log_p20260403 OWNER TO gtmsmanager;

--
-- Name: tab_ux_inform_log_p20260404; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_ux_inform_log_p20260404 (
    id bigint DEFAULT nextval('public.tab_ux_inform_log_id_seq'::regclass) NOT NULL,
    serial_number character varying(128),
    device_type character varying(32),
    sync_type smallint,
    oui character varying(32),
    product_class character varying(128),
    manufacturer character varying(128),
    success smallint NOT NULL,
    error_msg character varying(1024),
    create_time bigint NOT NULL
);


ALTER TABLE public.tab_ux_inform_log_p20260404 OWNER TO gtmsmanager;

--
-- Name: tab_ux_inform_log_p20260405; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_ux_inform_log_p20260405 (
    id bigint DEFAULT nextval('public.tab_ux_inform_log_id_seq'::regclass) NOT NULL,
    serial_number character varying(128),
    device_type character varying(32),
    sync_type smallint,
    oui character varying(32),
    product_class character varying(128),
    manufacturer character varying(128),
    success smallint NOT NULL,
    error_msg character varying(1024),
    create_time bigint NOT NULL
);


ALTER TABLE public.tab_ux_inform_log_p20260405 OWNER TO gtmsmanager;

--
-- Name: tab_ux_inform_log_p20260406; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_ux_inform_log_p20260406 (
    id bigint DEFAULT nextval('public.tab_ux_inform_log_id_seq'::regclass) NOT NULL,
    serial_number character varying(128),
    device_type character varying(32),
    sync_type smallint,
    oui character varying(32),
    product_class character varying(128),
    manufacturer character varying(128),
    success smallint NOT NULL,
    error_msg character varying(1024),
    create_time bigint NOT NULL
);


ALTER TABLE public.tab_ux_inform_log_p20260406 OWNER TO gtmsmanager;

--
-- Name: tab_ux_inform_log_p20260407; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_ux_inform_log_p20260407 (
    id bigint DEFAULT nextval('public.tab_ux_inform_log_id_seq'::regclass) NOT NULL,
    serial_number character varying(128),
    device_type character varying(32),
    sync_type smallint,
    oui character varying(32),
    product_class character varying(128),
    manufacturer character varying(128),
    success smallint NOT NULL,
    error_msg character varying(1024),
    create_time bigint NOT NULL
);


ALTER TABLE public.tab_ux_inform_log_p20260407 OWNER TO gtmsmanager;

--
-- Name: tab_ux_inform_log_p20260408; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_ux_inform_log_p20260408 (
    id bigint DEFAULT nextval('public.tab_ux_inform_log_id_seq'::regclass) NOT NULL,
    serial_number character varying(128),
    device_type character varying(32),
    sync_type smallint,
    oui character varying(32),
    product_class character varying(128),
    manufacturer character varying(128),
    success smallint NOT NULL,
    error_msg character varying(1024),
    create_time bigint NOT NULL
);


ALTER TABLE public.tab_ux_inform_log_p20260408 OWNER TO gtmsmanager;

--
-- Name: tab_ux_inform_log_p20260409; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_ux_inform_log_p20260409 (
    id bigint DEFAULT nextval('public.tab_ux_inform_log_id_seq'::regclass) NOT NULL,
    serial_number character varying(128),
    device_type character varying(32),
    sync_type smallint,
    oui character varying(32),
    product_class character varying(128),
    manufacturer character varying(128),
    success smallint NOT NULL,
    error_msg character varying(1024),
    create_time bigint NOT NULL
);


ALTER TABLE public.tab_ux_inform_log_p20260409 OWNER TO gtmsmanager;

--
-- Name: tab_ux_inform_log_p20260410; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_ux_inform_log_p20260410 (
    id bigint DEFAULT nextval('public.tab_ux_inform_log_id_seq'::regclass) NOT NULL,
    serial_number character varying(128),
    device_type character varying(32),
    sync_type smallint,
    oui character varying(32),
    product_class character varying(128),
    manufacturer character varying(128),
    success smallint NOT NULL,
    error_msg character varying(1024),
    create_time bigint NOT NULL
);


ALTER TABLE public.tab_ux_inform_log_p20260410 OWNER TO gtmsmanager;

--
-- Name: tab_ux_inform_log_p20260411; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_ux_inform_log_p20260411 (
    id bigint DEFAULT nextval('public.tab_ux_inform_log_id_seq'::regclass) NOT NULL,
    serial_number character varying(128),
    device_type character varying(32),
    sync_type smallint,
    oui character varying(32),
    product_class character varying(128),
    manufacturer character varying(128),
    success smallint NOT NULL,
    error_msg character varying(1024),
    create_time bigint NOT NULL
);


ALTER TABLE public.tab_ux_inform_log_p20260411 OWNER TO gtmsmanager;

--
-- Name: tab_ux_inform_log_p20260412; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_ux_inform_log_p20260412 (
    id bigint DEFAULT nextval('public.tab_ux_inform_log_id_seq'::regclass) NOT NULL,
    serial_number character varying(128),
    device_type character varying(32),
    sync_type smallint,
    oui character varying(32),
    product_class character varying(128),
    manufacturer character varying(128),
    success smallint NOT NULL,
    error_msg character varying(1024),
    create_time bigint NOT NULL
);


ALTER TABLE public.tab_ux_inform_log_p20260412 OWNER TO gtmsmanager;

--
-- Name: tab_ux_inform_log_p20260413; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_ux_inform_log_p20260413 (
    id bigint DEFAULT nextval('public.tab_ux_inform_log_id_seq'::regclass) NOT NULL,
    serial_number character varying(128),
    device_type character varying(32),
    sync_type smallint,
    oui character varying(32),
    product_class character varying(128),
    manufacturer character varying(128),
    success smallint NOT NULL,
    error_msg character varying(1024),
    create_time bigint NOT NULL
);


ALTER TABLE public.tab_ux_inform_log_p20260413 OWNER TO gtmsmanager;

--
-- Name: tab_ux_inform_log_p20260414; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_ux_inform_log_p20260414 (
    id bigint DEFAULT nextval('public.tab_ux_inform_log_id_seq'::regclass) NOT NULL,
    serial_number character varying(128),
    device_type character varying(32),
    sync_type smallint,
    oui character varying(32),
    product_class character varying(128),
    manufacturer character varying(128),
    success smallint NOT NULL,
    error_msg character varying(1024),
    create_time bigint NOT NULL
);


ALTER TABLE public.tab_ux_inform_log_p20260414 OWNER TO gtmsmanager;

--
-- Name: tab_ux_inform_log_p20260415; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_ux_inform_log_p20260415 (
    id bigint DEFAULT nextval('public.tab_ux_inform_log_id_seq'::regclass) NOT NULL,
    serial_number character varying(128),
    device_type character varying(32),
    sync_type smallint,
    oui character varying(32),
    product_class character varying(128),
    manufacturer character varying(128),
    success smallint NOT NULL,
    error_msg character varying(1024),
    create_time bigint NOT NULL
);


ALTER TABLE public.tab_ux_inform_log_p20260415 OWNER TO gtmsmanager;

--
-- Name: tab_ux_inform_log_p20260416; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_ux_inform_log_p20260416 (
    id bigint DEFAULT nextval('public.tab_ux_inform_log_id_seq'::regclass) NOT NULL,
    serial_number character varying(128),
    device_type character varying(32),
    sync_type smallint,
    oui character varying(32),
    product_class character varying(128),
    manufacturer character varying(128),
    success smallint NOT NULL,
    error_msg character varying(1024),
    create_time bigint NOT NULL
);


ALTER TABLE public.tab_ux_inform_log_p20260416 OWNER TO gtmsmanager;

--
-- Name: tab_ux_inform_log_p20260417; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_ux_inform_log_p20260417 (
    id bigint DEFAULT nextval('public.tab_ux_inform_log_id_seq'::regclass) NOT NULL,
    serial_number character varying(128),
    device_type character varying(32),
    sync_type smallint,
    oui character varying(32),
    product_class character varying(128),
    manufacturer character varying(128),
    success smallint NOT NULL,
    error_msg character varying(1024),
    create_time bigint NOT NULL
);


ALTER TABLE public.tab_ux_inform_log_p20260417 OWNER TO gtmsmanager;

--
-- Name: tab_ux_inform_log_p20260418; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_ux_inform_log_p20260418 (
    id bigint DEFAULT nextval('public.tab_ux_inform_log_id_seq'::regclass) NOT NULL,
    serial_number character varying(128),
    device_type character varying(32),
    sync_type smallint,
    oui character varying(32),
    product_class character varying(128),
    manufacturer character varying(128),
    success smallint NOT NULL,
    error_msg character varying(1024),
    create_time bigint NOT NULL
);


ALTER TABLE public.tab_ux_inform_log_p20260418 OWNER TO gtmsmanager;

--
-- Name: tab_ux_inform_log_p20260419; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_ux_inform_log_p20260419 (
    id bigint DEFAULT nextval('public.tab_ux_inform_log_id_seq'::regclass) NOT NULL,
    serial_number character varying(128),
    device_type character varying(32),
    sync_type smallint,
    oui character varying(32),
    product_class character varying(128),
    manufacturer character varying(128),
    success smallint NOT NULL,
    error_msg character varying(1024),
    create_time bigint NOT NULL
);


ALTER TABLE public.tab_ux_inform_log_p20260419 OWNER TO gtmsmanager;

--
-- Name: tab_ux_inform_log_p20260420; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_ux_inform_log_p20260420 (
    id bigint DEFAULT nextval('public.tab_ux_inform_log_id_seq'::regclass) NOT NULL,
    serial_number character varying(128),
    device_type character varying(32),
    sync_type smallint,
    oui character varying(32),
    product_class character varying(128),
    manufacturer character varying(128),
    success smallint NOT NULL,
    error_msg character varying(1024),
    create_time bigint NOT NULL
);


ALTER TABLE public.tab_ux_inform_log_p20260420 OWNER TO gtmsmanager;

--
-- Name: tab_ux_inform_log_p20260421; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_ux_inform_log_p20260421 (
    id bigint DEFAULT nextval('public.tab_ux_inform_log_id_seq'::regclass) NOT NULL,
    serial_number character varying(128),
    device_type character varying(32),
    sync_type smallint,
    oui character varying(32),
    product_class character varying(128),
    manufacturer character varying(128),
    success smallint NOT NULL,
    error_msg character varying(1024),
    create_time bigint NOT NULL
);


ALTER TABLE public.tab_ux_inform_log_p20260421 OWNER TO gtmsmanager;

--
-- Name: tab_ux_inform_log_p20260422; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_ux_inform_log_p20260422 (
    id bigint DEFAULT nextval('public.tab_ux_inform_log_id_seq'::regclass) NOT NULL,
    serial_number character varying(128),
    device_type character varying(32),
    sync_type smallint,
    oui character varying(32),
    product_class character varying(128),
    manufacturer character varying(128),
    success smallint NOT NULL,
    error_msg character varying(1024),
    create_time bigint NOT NULL
);


ALTER TABLE public.tab_ux_inform_log_p20260422 OWNER TO gtmsmanager;

--
-- Name: tab_ux_inform_log_p20260423; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_ux_inform_log_p20260423 (
    id bigint DEFAULT nextval('public.tab_ux_inform_log_id_seq'::regclass) NOT NULL,
    serial_number character varying(128),
    device_type character varying(32),
    sync_type smallint,
    oui character varying(32),
    product_class character varying(128),
    manufacturer character varying(128),
    success smallint NOT NULL,
    error_msg character varying(1024),
    create_time bigint NOT NULL
);


ALTER TABLE public.tab_ux_inform_log_p20260423 OWNER TO gtmsmanager;

--
-- Name: tab_ux_inform_log_zss; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_ux_inform_log_zss (
    id bigint,
    serial_number character varying(128),
    device_type character varying(32),
    sync_type smallint,
    oui character varying(32),
    product_class character varying(128),
    manufacturer character varying(128),
    success smallint,
    error_msg character varying(1024),
    create_time bigint
);


ALTER TABLE public.tab_ux_inform_log_zss OWNER TO gtmsmanager;

--
-- Name: tab_vendor; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_vendor (
    vendor_id character varying(6) NOT NULL,
    vendor_name character varying(64) NOT NULL,
    vendor_add character varying(50) NOT NULL,
    telephone character varying(20),
    staff_id character varying(30),
    remark character varying(100),
    add_time numeric(10,0) NOT NULL
);


ALTER TABLE public.tab_vendor OWNER TO gtmsmanager;

--
-- Name: COLUMN tab_vendor.add_time; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_vendor.add_time IS '秒';


--
-- Name: tab_vendor_ieee; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_vendor_ieee (
    vendor_id character varying(255) NOT NULL,
    oui character varying(255) DEFAULT NULL::character varying,
    vendor_name character varying(255) DEFAULT NULL::character varying,
    vendor_add character varying(500) DEFAULT NULL::character varying
);


ALTER TABLE public.tab_vendor_ieee OWNER TO gtmsmanager;

--
-- Name: TABLE tab_vendor_ieee; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON TABLE public.tab_vendor_ieee IS 'IEEE厂商信息表';


--
-- Name: COLUMN tab_vendor_ieee.vendor_id; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_vendor_ieee.vendor_id IS '厂商ID';


--
-- Name: COLUMN tab_vendor_ieee.oui; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_vendor_ieee.oui IS 'OUI标识';


--
-- Name: COLUMN tab_vendor_ieee.vendor_name; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_vendor_ieee.vendor_name IS '厂商名称';


--
-- Name: COLUMN tab_vendor_ieee.vendor_add; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_vendor_ieee.vendor_add IS '厂商地址';


--
-- Name: tab_vendor_oui; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_vendor_oui (
    vendor_id character varying(6) NOT NULL,
    oui character varying(6) NOT NULL
);


ALTER TABLE public.tab_vendor_oui OWNER TO gtmsmanager;

--
-- Name: tab_vercon_file; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_vercon_file (
    verconfile_id numeric(4,0) NOT NULL,
    verconfile_name character varying(100) NOT NULL,
    verconfile_description character varying(200),
    verconfile_size numeric(10,0),
    dir_id numeric(10,0) NOT NULL,
    verconfile_status numeric(1,0) NOT NULL,
    verconfile_isexist numeric(1,0) NOT NULL,
    devicetype_id numeric(4,0),
    device_id character varying(50),
    area_id numeric(10,0),
    gw_type character varying(1)
);


ALTER TABLE public.tab_vercon_file OWNER TO gtmsmanager;

--
-- Name: COLUMN tab_vercon_file.verconfile_status; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_vercon_file.verconfile_status IS '版本/配置模板文件状态1已审2未审';


--
-- Name: COLUMN tab_vercon_file.verconfile_isexist; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_vercon_file.verconfile_isexist IS '逻辑：
1：存在
0：不存在
';


--
-- Name: COLUMN tab_vercon_file.gw_type; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_vercon_file.gw_type IS '1.����������2.��������';


--
-- Name: tab_version_type; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_version_type (
    device_version_type numeric(2,0),
    version_type_name character varying(20),
    relation_version_type numeric(2,0)
);


ALTER TABLE public.tab_version_type OWNER TO gtmsmanager;

--
-- Name: tab_voice_ping_param; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_voice_ping_param (
    id numeric(10,0) NOT NULL,
    city_id character varying(20) NOT NULL,
    protocol numeric(2,0) NOT NULL,
    ping_ip character varying(40) NOT NULL,
    package_byte numeric(10,0) NOT NULL,
    package_num numeric(3,0) NOT NULL,
    timeout numeric(10,0) NOT NULL
);


ALTER TABLE public.tab_voice_ping_param OWNER TO gtmsmanager;

--
-- Name: tab_voip_serv_param; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_voip_serv_param (
    user_id bigint NOT NULL,
    line_id smallint NOT NULL,
    voip_username character varying(256),
    voip_passwd character varying(128),
    sip_id integer,
    updatetime bigint DEFAULT 0 NOT NULL,
    voip_phone character varying(13),
    parm_stat smallint DEFAULT 0 NOT NULL,
    protocol smallint NOT NULL,
    voip_port character varying(128),
    reg_id character varying(30),
    reg_id_type smallint,
    uri character varying(50),
    user_agent_domain character varying(50),
    digit_map character varying(10),
    rtp_prefix character varying(20),
    termid_add_len smallint,
    termid_start smallint,
    rtp_tid character varying(20),
    value_802_1p character varying(50),
    eid integer,
    device_name character varying(50),
    dscp_mark character varying(50),
    user_agent_port character varying(10),
    exec_time integer,
    open_status integer,
    termid_uniform integer,
    messageencodingtype integer,
    deal_type integer
);


ALTER TABLE public.tab_voip_serv_param OWNER TO gtmsmanager;

--
-- Name: tab_vxlan_forwarding_config; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_vxlan_forwarding_config (
    user_id numeric(10,0) NOT NULL,
    rt_id character varying(50),
    next_hop character varying(50) NOT NULL,
    des_ip character varying(50) NOT NULL,
    priority character varying(5),
    state numeric(2,0)
);


ALTER TABLE public.tab_vxlan_forwarding_config OWNER TO gtmsmanager;

--
-- Name: tab_vxlan_nat_config; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_vxlan_nat_config (
    user_id numeric(10,0) NOT NULL,
    pub_ipv4 character varying(50) NOT NULL,
    pub_port character varying(50),
    priv_ipv4 character varying(50) NOT NULL,
    priv_port character varying(50),
    protocol character varying(50),
    state numeric(2,0)
);


ALTER TABLE public.tab_vxlan_nat_config OWNER TO gtmsmanager;

--
-- Name: tab_vxlan_serv_param; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_vxlan_serv_param (
    user_id numeric(10,0) NOT NULL,
    serv_type_id numeric(4,0) NOT NULL,
    username character varying(50) NOT NULL,
    serv_status numeric(1,0),
    open_status numeric(1,0),
    request_id character varying(50),
    tunnel_key numeric(10,0),
    tunnel_remote_ip character varying(50),
    workmode numeric(4,0),
    maxmtusize numeric(10,0),
    ip_address character varying(50),
    subnetmask character varying(50),
    addressing_type character varying(50),
    natenabled numeric(1,0),
    dnsservers_master character varying(50),
    dnsservers_slave character varying(50),
    defaultgateway character varying(50),
    xctcom_vlan numeric(10,0),
    updatetime numeric(10,0),
    open_date numeric(10,0),
    completedate numeric(10,0),
    bind_port character varying(255),
    vxlanconfigsequence numeric(5,0) NOT NULL
);


ALTER TABLE public.tab_vxlan_serv_param OWNER TO gtmsmanager;

--
-- Name: tab_whitelist_dev; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_whitelist_dev (
    device_id character varying(64) NOT NULL,
    device_serialnumber character varying(64) NOT NULL,
    task_type integer NOT NULL,
    add_time numeric(10,0) NOT NULL
);


ALTER TABLE public.tab_whitelist_dev OWNER TO gtmsmanager;

--
-- Name: tab_wirelesst_task; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_wirelesst_task (
    task_id numeric(10,0) NOT NULL,
    acc_oid numeric(14,0) NOT NULL,
    add_time numeric(10,0),
    service_id numeric(4,0),
    vlan_id numeric(2,0),
    ssid character varying(200),
    strategy_type character varying(10),
    wireless_port numeric(2,0),
    buss_level numeric(2,0),
    wireless_type numeric(1,0),
    channel character varying(10)
);


ALTER TABLE public.tab_wirelesst_task OWNER TO gtmsmanager;

--
-- Name: tab_wirelesst_task_dev; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_wirelesst_task_dev (
    task_id numeric(10,0) NOT NULL,
    device_id character varying(10) NOT NULL,
    oui character varying(6),
    device_serialnumber character varying(64),
    loid character varying(64),
    result_id numeric(10,0),
    status numeric(2,0)
);


ALTER TABLE public.tab_wirelesst_task_dev OWNER TO gtmsmanager;

--
-- Name: tab_xjdx_nomatchreport; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_xjdx_nomatchreport (
    city_id character varying(20) NOT NULL,
    city_name character varying(30) NOT NULL,
    t0num numeric(10,0) NOT NULL,
    daynomatchnum numeric(10,0) NOT NULL,
    allnomatchnum numeric(10,0) NOT NULL,
    scrapdevnum numeric(10,0) NOT NULL,
    alladdnomatchnum numeric(10,0) NOT NULL,
    old_t0num numeric(10,0) NOT NULL,
    old_onuse_num numeric(10,0) NOT NULL,
    old_day_complt_num numeric(10,0),
    sec_t0 numeric(10,0),
    sec_nocplt_num numeric(10,0),
    thrd_t0 numeric(10,0),
    thrd_nocplt_num numeric(10,0),
    old_all_complt_num numeric(10,0)
);


ALTER TABLE public.tab_xjdx_nomatchreport OWNER TO gtmsmanager;

--
-- Name: tab_zeroconfig_report; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_zeroconfig_report (
    cmdid character varying(20) NOT NULL,
    cmd_type character varying(50) NOT NULL,
    client_type numeric(2,0) NOT NULL,
    service_type numeric(2,0) NOT NULL,
    operate_type numeric(2,0) NOT NULL,
    user_info character varying(30) NOT NULL,
    device_sn character varying(50),
    update_time numeric(10,0) NOT NULL,
    inft_result numeric(2,0),
    bind_result numeric(5,0) NOT NULL,
    bind_time numeric(10,0),
    city_id character varying(20) NOT NULL
);


ALTER TABLE public.tab_zeroconfig_report OWNER TO gtmsmanager;

--
-- Name: COLUMN tab_zeroconfig_report.client_type; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_zeroconfig_report.client_type IS '1��BSS
2��IPOSS
3������
4��RADIUS
5����������';


--
-- Name: COLUMN tab_zeroconfig_report.service_type; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_zeroconfig_report.service_type IS '1����������e8-b
2����������e8-c
3����������
4��������';


--
-- Name: COLUMN tab_zeroconfig_report.operate_type; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_zeroconfig_report.operate_type IS '1������
2������';


--
-- Name: COLUMN tab_zeroconfig_report.inft_result; Type: COMMENT; Schema: public; Owner: gtmsmanager
--

COMMENT ON COLUMN public.tab_zeroconfig_report.inft_result IS '1����������
-1����������
2������������
3������������';


--
-- Name: tab_zeroconfig_res_day; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_zeroconfig_res_day (
    city_name character varying(50),
    countall numeric(5,0),
    netsucc numeric(5,0),
    iptvsucc numeric(5,0),
    voipsucc numeric(5,0),
    date_time character varying(50)
);


ALTER TABLE public.tab_zeroconfig_res_day OWNER TO gtmsmanager;

--
-- Name: tab_zeroconfig_res_minute; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_zeroconfig_res_minute (
    city_name character varying(50),
    countall numeric(5,0),
    netsucc numeric(5,0),
    iptvsucc numeric(5,0),
    voipsucc numeric(5,0),
    add_time numeric(10,0)
);


ALTER TABLE public.tab_zeroconfig_res_minute OWNER TO gtmsmanager;

--
-- Name: tab_zone; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.tab_zone (
    zone_id character varying(20) NOT NULL,
    zone_name character varying(50) NOT NULL,
    staff_id character varying(30),
    remark character varying(100)
);


ALTER TABLE public.tab_zone OWNER TO gtmsmanager;

--
-- Name: user_type; Type: TABLE; Schema: public; Owner: gtmsmanager
--

CREATE TABLE public.user_type (
    user_type_id character varying(2) NOT NULL,
    type_name character varying(30) NOT NULL,
    remark character varying(50)
);


ALTER TABLE public.user_type OWNER TO gtmsmanager;

--
-- Name: tab_capacity_log_default; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_capacity_log ATTACH PARTITION public.tab_capacity_log_default DEFAULT;


--
-- Name: tab_capacity_log_p20260323; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_capacity_log ATTACH PARTITION public.tab_capacity_log_p20260323 FOR VALUES FROM (1774224000) TO (1774310400);


--
-- Name: tab_capacity_log_p20260324; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_capacity_log ATTACH PARTITION public.tab_capacity_log_p20260324 FOR VALUES FROM (1774310400) TO (1774396800);


--
-- Name: tab_capacity_log_p20260325; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_capacity_log ATTACH PARTITION public.tab_capacity_log_p20260325 FOR VALUES FROM (1774396800) TO (1774483200);


--
-- Name: tab_capacity_log_p20260326; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_capacity_log ATTACH PARTITION public.tab_capacity_log_p20260326 FOR VALUES FROM (1774483200) TO (1774569600);


--
-- Name: tab_capacity_log_p20260327; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_capacity_log ATTACH PARTITION public.tab_capacity_log_p20260327 FOR VALUES FROM (1774569600) TO (1774656000);


--
-- Name: tab_capacity_log_p20260328; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_capacity_log ATTACH PARTITION public.tab_capacity_log_p20260328 FOR VALUES FROM (1774656000) TO (1774742400);


--
-- Name: tab_capacity_log_p20260329; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_capacity_log ATTACH PARTITION public.tab_capacity_log_p20260329 FOR VALUES FROM (1774742400) TO (1774828800);


--
-- Name: tab_capacity_log_p20260330; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_capacity_log ATTACH PARTITION public.tab_capacity_log_p20260330 FOR VALUES FROM (1774828800) TO (1774915200);


--
-- Name: tab_capacity_log_p20260331; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_capacity_log ATTACH PARTITION public.tab_capacity_log_p20260331 FOR VALUES FROM (1774915200) TO (1775001600);


--
-- Name: tab_capacity_log_p20260401; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_capacity_log ATTACH PARTITION public.tab_capacity_log_p20260401 FOR VALUES FROM (1775001600) TO (1775088000);


--
-- Name: tab_capacity_log_p20260402; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_capacity_log ATTACH PARTITION public.tab_capacity_log_p20260402 FOR VALUES FROM (1775088000) TO (1775174400);


--
-- Name: tab_capacity_log_p20260403; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_capacity_log ATTACH PARTITION public.tab_capacity_log_p20260403 FOR VALUES FROM (1775174400) TO (1775260800);


--
-- Name: tab_capacity_log_p20260404; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_capacity_log ATTACH PARTITION public.tab_capacity_log_p20260404 FOR VALUES FROM (1775260800) TO (1775347200);


--
-- Name: tab_capacity_log_p20260405; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_capacity_log ATTACH PARTITION public.tab_capacity_log_p20260405 FOR VALUES FROM (1775347200) TO (1775433600);


--
-- Name: tab_capacity_log_p20260406; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_capacity_log ATTACH PARTITION public.tab_capacity_log_p20260406 FOR VALUES FROM (1775433600) TO (1775520000);


--
-- Name: tab_capacity_log_p20260407; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_capacity_log ATTACH PARTITION public.tab_capacity_log_p20260407 FOR VALUES FROM (1775520000) TO (1775606400);


--
-- Name: tab_capacity_log_p20260408; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_capacity_log ATTACH PARTITION public.tab_capacity_log_p20260408 FOR VALUES FROM (1775606400) TO (1775692800);


--
-- Name: tab_capacity_log_p20260409; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_capacity_log ATTACH PARTITION public.tab_capacity_log_p20260409 FOR VALUES FROM (1775692800) TO (1775779200);


--
-- Name: tab_capacity_log_p20260410; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_capacity_log ATTACH PARTITION public.tab_capacity_log_p20260410 FOR VALUES FROM (1775779200) TO (1775865600);


--
-- Name: tab_capacity_log_p20260411; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_capacity_log ATTACH PARTITION public.tab_capacity_log_p20260411 FOR VALUES FROM (1775865600) TO (1775952000);


--
-- Name: tab_capacity_log_p20260412; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_capacity_log ATTACH PARTITION public.tab_capacity_log_p20260412 FOR VALUES FROM (1775952000) TO (1776038400);


--
-- Name: tab_capacity_log_p20260413; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_capacity_log ATTACH PARTITION public.tab_capacity_log_p20260413 FOR VALUES FROM (1776038400) TO (1776124800);


--
-- Name: tab_capacity_log_p20260414; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_capacity_log ATTACH PARTITION public.tab_capacity_log_p20260414 FOR VALUES FROM (1776124800) TO (1776211200);


--
-- Name: tab_capacity_log_p20260415; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_capacity_log ATTACH PARTITION public.tab_capacity_log_p20260415 FOR VALUES FROM (1776211200) TO (1776297600);


--
-- Name: tab_capacity_log_p20260416; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_capacity_log ATTACH PARTITION public.tab_capacity_log_p20260416 FOR VALUES FROM (1776297600) TO (1776384000);


--
-- Name: tab_capacity_log_p20260417; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_capacity_log ATTACH PARTITION public.tab_capacity_log_p20260417 FOR VALUES FROM (1776384000) TO (1776470400);


--
-- Name: tab_capacity_log_p20260418; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_capacity_log ATTACH PARTITION public.tab_capacity_log_p20260418 FOR VALUES FROM (1776470400) TO (1776556800);


--
-- Name: tab_capacity_log_p20260419; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_capacity_log ATTACH PARTITION public.tab_capacity_log_p20260419 FOR VALUES FROM (1776556800) TO (1776643200);


--
-- Name: tab_capacity_log_p20260420; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_capacity_log ATTACH PARTITION public.tab_capacity_log_p20260420 FOR VALUES FROM (1776643200) TO (1776729600);


--
-- Name: tab_capacity_log_p20260421; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_capacity_log ATTACH PARTITION public.tab_capacity_log_p20260421 FOR VALUES FROM (1776729600) TO (1776816000);


--
-- Name: tab_capacity_log_p20260422; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_capacity_log ATTACH PARTITION public.tab_capacity_log_p20260422 FOR VALUES FROM (1776816000) TO (1776902400);


--
-- Name: tab_capacity_log_p20260423; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_capacity_log ATTACH PARTITION public.tab_capacity_log_p20260423 FOR VALUES FROM (1776902400) TO (1776988800);


--
-- Name: tab_capacity_log_parameter_default; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_capacity_log_parameter ATTACH PARTITION public.tab_capacity_log_parameter_default DEFAULT;


--
-- Name: tab_capacity_log_parameter_p20260323; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_capacity_log_parameter ATTACH PARTITION public.tab_capacity_log_parameter_p20260323 FOR VALUES FROM (1774224000) TO (1774310400);


--
-- Name: tab_capacity_log_parameter_p20260324; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_capacity_log_parameter ATTACH PARTITION public.tab_capacity_log_parameter_p20260324 FOR VALUES FROM (1774310400) TO (1774396800);


--
-- Name: tab_capacity_log_parameter_p20260325; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_capacity_log_parameter ATTACH PARTITION public.tab_capacity_log_parameter_p20260325 FOR VALUES FROM (1774396800) TO (1774483200);


--
-- Name: tab_capacity_log_parameter_p20260326; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_capacity_log_parameter ATTACH PARTITION public.tab_capacity_log_parameter_p20260326 FOR VALUES FROM (1774483200) TO (1774569600);


--
-- Name: tab_capacity_log_parameter_p20260327; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_capacity_log_parameter ATTACH PARTITION public.tab_capacity_log_parameter_p20260327 FOR VALUES FROM (1774569600) TO (1774656000);


--
-- Name: tab_capacity_log_parameter_p20260328; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_capacity_log_parameter ATTACH PARTITION public.tab_capacity_log_parameter_p20260328 FOR VALUES FROM (1774656000) TO (1774742400);


--
-- Name: tab_capacity_log_parameter_p20260329; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_capacity_log_parameter ATTACH PARTITION public.tab_capacity_log_parameter_p20260329 FOR VALUES FROM (1774742400) TO (1774828800);


--
-- Name: tab_capacity_log_parameter_p20260330; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_capacity_log_parameter ATTACH PARTITION public.tab_capacity_log_parameter_p20260330 FOR VALUES FROM (1774828800) TO (1774915200);


--
-- Name: tab_capacity_log_parameter_p20260331; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_capacity_log_parameter ATTACH PARTITION public.tab_capacity_log_parameter_p20260331 FOR VALUES FROM (1774915200) TO (1775001600);


--
-- Name: tab_capacity_log_parameter_p20260401; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_capacity_log_parameter ATTACH PARTITION public.tab_capacity_log_parameter_p20260401 FOR VALUES FROM (1775001600) TO (1775088000);


--
-- Name: tab_capacity_log_parameter_p20260402; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_capacity_log_parameter ATTACH PARTITION public.tab_capacity_log_parameter_p20260402 FOR VALUES FROM (1775088000) TO (1775174400);


--
-- Name: tab_capacity_log_parameter_p20260403; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_capacity_log_parameter ATTACH PARTITION public.tab_capacity_log_parameter_p20260403 FOR VALUES FROM (1775174400) TO (1775260800);


--
-- Name: tab_capacity_log_parameter_p20260404; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_capacity_log_parameter ATTACH PARTITION public.tab_capacity_log_parameter_p20260404 FOR VALUES FROM (1775260800) TO (1775347200);


--
-- Name: tab_capacity_log_parameter_p20260405; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_capacity_log_parameter ATTACH PARTITION public.tab_capacity_log_parameter_p20260405 FOR VALUES FROM (1775347200) TO (1775433600);


--
-- Name: tab_capacity_log_parameter_p20260406; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_capacity_log_parameter ATTACH PARTITION public.tab_capacity_log_parameter_p20260406 FOR VALUES FROM (1775433600) TO (1775520000);


--
-- Name: tab_capacity_log_parameter_p20260407; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_capacity_log_parameter ATTACH PARTITION public.tab_capacity_log_parameter_p20260407 FOR VALUES FROM (1775520000) TO (1775606400);


--
-- Name: tab_capacity_log_parameter_p20260408; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_capacity_log_parameter ATTACH PARTITION public.tab_capacity_log_parameter_p20260408 FOR VALUES FROM (1775606400) TO (1775692800);


--
-- Name: tab_capacity_log_parameter_p20260409; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_capacity_log_parameter ATTACH PARTITION public.tab_capacity_log_parameter_p20260409 FOR VALUES FROM (1775692800) TO (1775779200);


--
-- Name: tab_capacity_log_parameter_p20260410; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_capacity_log_parameter ATTACH PARTITION public.tab_capacity_log_parameter_p20260410 FOR VALUES FROM (1775779200) TO (1775865600);


--
-- Name: tab_capacity_log_parameter_p20260411; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_capacity_log_parameter ATTACH PARTITION public.tab_capacity_log_parameter_p20260411 FOR VALUES FROM (1775865600) TO (1775952000);


--
-- Name: tab_capacity_log_parameter_p20260412; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_capacity_log_parameter ATTACH PARTITION public.tab_capacity_log_parameter_p20260412 FOR VALUES FROM (1775952000) TO (1776038400);


--
-- Name: tab_capacity_log_parameter_p20260413; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_capacity_log_parameter ATTACH PARTITION public.tab_capacity_log_parameter_p20260413 FOR VALUES FROM (1776038400) TO (1776124800);


--
-- Name: tab_capacity_log_parameter_p20260414; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_capacity_log_parameter ATTACH PARTITION public.tab_capacity_log_parameter_p20260414 FOR VALUES FROM (1776124800) TO (1776211200);


--
-- Name: tab_capacity_log_parameter_p20260415; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_capacity_log_parameter ATTACH PARTITION public.tab_capacity_log_parameter_p20260415 FOR VALUES FROM (1776211200) TO (1776297600);


--
-- Name: tab_capacity_log_parameter_p20260416; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_capacity_log_parameter ATTACH PARTITION public.tab_capacity_log_parameter_p20260416 FOR VALUES FROM (1776297600) TO (1776384000);


--
-- Name: tab_capacity_log_parameter_p20260417; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_capacity_log_parameter ATTACH PARTITION public.tab_capacity_log_parameter_p20260417 FOR VALUES FROM (1776384000) TO (1776470400);


--
-- Name: tab_capacity_log_parameter_p20260418; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_capacity_log_parameter ATTACH PARTITION public.tab_capacity_log_parameter_p20260418 FOR VALUES FROM (1776470400) TO (1776556800);


--
-- Name: tab_capacity_log_parameter_p20260419; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_capacity_log_parameter ATTACH PARTITION public.tab_capacity_log_parameter_p20260419 FOR VALUES FROM (1776556800) TO (1776643200);


--
-- Name: tab_capacity_log_parameter_p20260420; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_capacity_log_parameter ATTACH PARTITION public.tab_capacity_log_parameter_p20260420 FOR VALUES FROM (1776643200) TO (1776729600);


--
-- Name: tab_capacity_log_parameter_p20260421; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_capacity_log_parameter ATTACH PARTITION public.tab_capacity_log_parameter_p20260421 FOR VALUES FROM (1776729600) TO (1776816000);


--
-- Name: tab_capacity_log_parameter_p20260422; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_capacity_log_parameter ATTACH PARTITION public.tab_capacity_log_parameter_p20260422 FOR VALUES FROM (1776816000) TO (1776902400);


--
-- Name: tab_capacity_log_parameter_p20260423; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_capacity_log_parameter ATTACH PARTITION public.tab_capacity_log_parameter_p20260423 FOR VALUES FROM (1776902400) TO (1776988800);


--
-- Name: tab_ux_inform_log_default; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_ux_inform_log ATTACH PARTITION public.tab_ux_inform_log_default DEFAULT;


--
-- Name: tab_ux_inform_log_p20260323; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_ux_inform_log ATTACH PARTITION public.tab_ux_inform_log_p20260323 FOR VALUES FROM ('1774224000') TO ('1774310400');


--
-- Name: tab_ux_inform_log_p20260324; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_ux_inform_log ATTACH PARTITION public.tab_ux_inform_log_p20260324 FOR VALUES FROM ('1774310400') TO ('1774396800');


--
-- Name: tab_ux_inform_log_p20260325; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_ux_inform_log ATTACH PARTITION public.tab_ux_inform_log_p20260325 FOR VALUES FROM ('1774396800') TO ('1774483200');


--
-- Name: tab_ux_inform_log_p20260326; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_ux_inform_log ATTACH PARTITION public.tab_ux_inform_log_p20260326 FOR VALUES FROM ('1774483200') TO ('1774569600');


--
-- Name: tab_ux_inform_log_p20260327; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_ux_inform_log ATTACH PARTITION public.tab_ux_inform_log_p20260327 FOR VALUES FROM ('1774569600') TO ('1774656000');


--
-- Name: tab_ux_inform_log_p20260328; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_ux_inform_log ATTACH PARTITION public.tab_ux_inform_log_p20260328 FOR VALUES FROM ('1774656000') TO ('1774742400');


--
-- Name: tab_ux_inform_log_p20260329; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_ux_inform_log ATTACH PARTITION public.tab_ux_inform_log_p20260329 FOR VALUES FROM ('1774742400') TO ('1774828800');


--
-- Name: tab_ux_inform_log_p20260330; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_ux_inform_log ATTACH PARTITION public.tab_ux_inform_log_p20260330 FOR VALUES FROM ('1774828800') TO ('1774915200');


--
-- Name: tab_ux_inform_log_p20260331; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_ux_inform_log ATTACH PARTITION public.tab_ux_inform_log_p20260331 FOR VALUES FROM ('1774915200') TO ('1775001600');


--
-- Name: tab_ux_inform_log_p20260401; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_ux_inform_log ATTACH PARTITION public.tab_ux_inform_log_p20260401 FOR VALUES FROM ('1775001600') TO ('1775088000');


--
-- Name: tab_ux_inform_log_p20260402; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_ux_inform_log ATTACH PARTITION public.tab_ux_inform_log_p20260402 FOR VALUES FROM ('1775088000') TO ('1775174400');


--
-- Name: tab_ux_inform_log_p20260403; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_ux_inform_log ATTACH PARTITION public.tab_ux_inform_log_p20260403 FOR VALUES FROM ('1775174400') TO ('1775260800');


--
-- Name: tab_ux_inform_log_p20260404; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_ux_inform_log ATTACH PARTITION public.tab_ux_inform_log_p20260404 FOR VALUES FROM ('1775260800') TO ('1775347200');


--
-- Name: tab_ux_inform_log_p20260405; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_ux_inform_log ATTACH PARTITION public.tab_ux_inform_log_p20260405 FOR VALUES FROM ('1775347200') TO ('1775433600');


--
-- Name: tab_ux_inform_log_p20260406; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_ux_inform_log ATTACH PARTITION public.tab_ux_inform_log_p20260406 FOR VALUES FROM ('1775433600') TO ('1775520000');


--
-- Name: tab_ux_inform_log_p20260407; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_ux_inform_log ATTACH PARTITION public.tab_ux_inform_log_p20260407 FOR VALUES FROM ('1775520000') TO ('1775606400');


--
-- Name: tab_ux_inform_log_p20260408; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_ux_inform_log ATTACH PARTITION public.tab_ux_inform_log_p20260408 FOR VALUES FROM ('1775606400') TO ('1775692800');


--
-- Name: tab_ux_inform_log_p20260409; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_ux_inform_log ATTACH PARTITION public.tab_ux_inform_log_p20260409 FOR VALUES FROM ('1775692800') TO ('1775779200');


--
-- Name: tab_ux_inform_log_p20260410; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_ux_inform_log ATTACH PARTITION public.tab_ux_inform_log_p20260410 FOR VALUES FROM ('1775779200') TO ('1775865600');


--
-- Name: tab_ux_inform_log_p20260411; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_ux_inform_log ATTACH PARTITION public.tab_ux_inform_log_p20260411 FOR VALUES FROM ('1775865600') TO ('1775952000');


--
-- Name: tab_ux_inform_log_p20260412; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_ux_inform_log ATTACH PARTITION public.tab_ux_inform_log_p20260412 FOR VALUES FROM ('1775952000') TO ('1776038400');


--
-- Name: tab_ux_inform_log_p20260413; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_ux_inform_log ATTACH PARTITION public.tab_ux_inform_log_p20260413 FOR VALUES FROM ('1776038400') TO ('1776124800');


--
-- Name: tab_ux_inform_log_p20260414; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_ux_inform_log ATTACH PARTITION public.tab_ux_inform_log_p20260414 FOR VALUES FROM ('1776124800') TO ('1776211200');


--
-- Name: tab_ux_inform_log_p20260415; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_ux_inform_log ATTACH PARTITION public.tab_ux_inform_log_p20260415 FOR VALUES FROM ('1776211200') TO ('1776297600');


--
-- Name: tab_ux_inform_log_p20260416; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_ux_inform_log ATTACH PARTITION public.tab_ux_inform_log_p20260416 FOR VALUES FROM ('1776297600') TO ('1776384000');


--
-- Name: tab_ux_inform_log_p20260417; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_ux_inform_log ATTACH PARTITION public.tab_ux_inform_log_p20260417 FOR VALUES FROM ('1776384000') TO ('1776470400');


--
-- Name: tab_ux_inform_log_p20260418; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_ux_inform_log ATTACH PARTITION public.tab_ux_inform_log_p20260418 FOR VALUES FROM ('1776470400') TO ('1776556800');


--
-- Name: tab_ux_inform_log_p20260419; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_ux_inform_log ATTACH PARTITION public.tab_ux_inform_log_p20260419 FOR VALUES FROM ('1776556800') TO ('1776643200');


--
-- Name: tab_ux_inform_log_p20260420; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_ux_inform_log ATTACH PARTITION public.tab_ux_inform_log_p20260420 FOR VALUES FROM ('1776643200') TO ('1776729600');


--
-- Name: tab_ux_inform_log_p20260421; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_ux_inform_log ATTACH PARTITION public.tab_ux_inform_log_p20260421 FOR VALUES FROM ('1776729600') TO ('1776816000');


--
-- Name: tab_ux_inform_log_p20260422; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_ux_inform_log ATTACH PARTITION public.tab_ux_inform_log_p20260422 FOR VALUES FROM ('1776816000') TO ('1776902400');


--
-- Name: tab_ux_inform_log_p20260423; Type: TABLE ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_ux_inform_log ATTACH PARTITION public.tab_ux_inform_log_p20260423 FOR VALUES FROM ('1776902400') TO ('1776988800');


--
-- Name: tab_cpe_classify_statistic id; Type: DEFAULT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_cpe_classify_statistic ALTER COLUMN id SET DEFAULT nextval('public.tab_cpe_classify_statistic_id_seq'::regclass);


--
-- Name: tab_serv_classify_statistic id; Type: DEFAULT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_serv_classify_statistic ALTER COLUMN id SET DEFAULT nextval('public.tab_serv_classify_statistic_id_seq'::regclass);


--
-- Name: tab_ux_inform_log_bak_20260324121914 id; Type: DEFAULT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_ux_inform_log_bak_20260324121914 ALTER COLUMN id SET DEFAULT nextval('public.tab_ux_inform_log_id_seq'::regclass);


--
-- Name: partition_config partition_config_pkey; Type: CONSTRAINT; Schema: partition_admin; Owner: gtmsmanager
--

ALTER TABLE ONLY partition_admin.partition_config
    ADD CONSTRAINT partition_config_pkey PRIMARY KEY (table_name);


--
-- Name: bind_log bind_log_pkey; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.bind_log
    ADD CONSTRAINT bind_log_pkey PRIMARY KEY (bind_id);


--
-- Name: bind_type bind_type_pkey; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.bind_type
    ADD CONSTRAINT bind_type_pkey PRIMARY KEY (bind_type_id);


--
-- Name: cpe_gather_config cpe_gather_config_pkey; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.cpe_gather_config
    ADD CONSTRAINT cpe_gather_config_pkey PRIMARY KEY (id, city_id);


--
-- Name: cpe_gather_node_tabname cpe_gather_node_tabname_pkey; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.cpe_gather_node_tabname
    ADD CONSTRAINT cpe_gather_node_tabname_pkey PRIMARY KEY (id);


--
-- Name: cpe_gather_param_type_bbms cpe_gather_param_type_bbms_pkey; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.cpe_gather_param_type_bbms
    ADD CONSTRAINT cpe_gather_param_type_bbms_pkey PRIMARY KEY (id);


--
-- Name: cpe_gather_param_type cpe_gather_param_type_pkey; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.cpe_gather_param_type
    ADD CONSTRAINT cpe_gather_param_type_pkey PRIMARY KEY (id);


--
-- Name: cpe_gather_record cpe_gather_record_pkey; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.cpe_gather_record
    ADD CONSTRAINT cpe_gather_record_pkey PRIMARY KEY (device_id, param_type);


--
-- Name: cpe_gather_result cpe_gather_result_pkey; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.cpe_gather_result
    ADD CONSTRAINT cpe_gather_result_pkey PRIMARY KEY (device_id, id);


--
-- Name: dev_event_type dev_event_type_pkey; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.dev_event_type
    ADD CONSTRAINT dev_event_type_pkey PRIMARY KEY (event_id);


--
-- Name: egw_item_role egw_item_role_pkey; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.egw_item_role
    ADD CONSTRAINT egw_item_role_pkey PRIMARY KEY (item_id, role_id);


--
-- Name: guangkuan_reboot_info guangkuan_reboot_info_pkey; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.guangkuan_reboot_info
    ADD CONSTRAINT guangkuan_reboot_info_pkey PRIMARY KEY (device_id, getinfodate);


--
-- Name: gw_access_type gw_access_type_pkey; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_access_type
    ADD CONSTRAINT gw_access_type_pkey PRIMARY KEY (type_id);


--
-- Name: gw_acs_stream gw_acs_stream_pkey; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_acs_stream
    ADD CONSTRAINT gw_acs_stream_pkey PRIMARY KEY (device_id, device_ip, toward, inter_time);


--
-- Name: gw_alg_bbms gw_alg_bbms_pkey; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_alg_bbms
    ADD CONSTRAINT gw_alg_bbms_pkey PRIMARY KEY (device_id);


--
-- Name: gw_alg gw_alg_pkey; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_alg
    ADD CONSTRAINT gw_alg_pkey PRIMARY KEY (device_id);


--
-- Name: gw_card_manage gw_card_manage_pkey; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_card_manage
    ADD CONSTRAINT gw_card_manage_pkey PRIMARY KEY (device_id);


--
-- Name: gw_conf_template gw_conf_template_pkey; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_conf_template
    ADD CONSTRAINT gw_conf_template_pkey PRIMARY KEY (temp_id);


--
-- Name: gw_conf_template_service gw_conf_template_service_pkey; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_conf_template_service
    ADD CONSTRAINT gw_conf_template_service_pkey PRIMARY KEY (temp_id, order_id);


--
-- Name: gw_cust_user_dev_type gw_cust_user_dev_type_pkey; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_cust_user_dev_type
    ADD CONSTRAINT gw_cust_user_dev_type_pkey PRIMARY KEY (customer_id, user_id, type_id);


--
-- Name: gw_cust_user_package gw_cust_user_package_pkey; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_cust_user_package
    ADD CONSTRAINT gw_cust_user_package_pkey PRIMARY KEY (user_id, serv_package_id);


--
-- Name: gw_devicestatus gw_devicestatus_pkey; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_devicestatus
    ADD CONSTRAINT gw_devicestatus_pkey PRIMARY KEY (device_id);


--
-- Name: gw_serv_beforehand gw_serv_beforehand_pkey; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_serv_beforehand
    ADD CONSTRAINT gw_serv_beforehand_pkey PRIMARY KEY (id);


--
-- Name: gw_cust_user_package_copy1 pk_gw_cust_user_package_copy1; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_cust_user_package_copy1
    ADD CONSTRAINT pk_gw_cust_user_package_copy1 PRIMARY KEY (user_id, serv_package_id);


--
-- Name: gw_dev_model_dev_type pk_gw_dev_model_dev_type; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_dev_model_dev_type
    ADD CONSTRAINT pk_gw_dev_model_dev_type PRIMARY KEY (device_model_id, type_id);


--
-- Name: gw_dev_serv pk_gw_dev_serv; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_dev_serv
    ADD CONSTRAINT pk_gw_dev_serv PRIMARY KEY (device_id, serv_type_id);


--
-- Name: gw_dev_type pk_gw_dev_type; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_dev_type
    ADD CONSTRAINT pk_gw_dev_type PRIMARY KEY (type_id);


--
-- Name: gw_device_model pk_gw_device_model; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_device_model
    ADD CONSTRAINT pk_gw_device_model PRIMARY KEY (device_model_id);


--
-- Name: gw_device_restart_batch pk_gw_device_restart_batch; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_device_restart_batch
    ADD CONSTRAINT pk_gw_device_restart_batch PRIMARY KEY (task_id, device_id);


--
-- Name: gw_device_restart_task pk_gw_device_restart_task; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_device_restart_task
    ADD CONSTRAINT pk_gw_device_restart_task PRIMARY KEY (task_id);


--
-- Name: gw_devicestatus_history pk_gw_devicestatus_history; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_devicestatus_history
    ADD CONSTRAINT pk_gw_devicestatus_history PRIMARY KEY (id);


--
-- Name: gw_egw_expert pk_gw_egw_expert; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_egw_expert
    ADD CONSTRAINT pk_gw_egw_expert PRIMARY KEY (id);


--
-- Name: gw_exception pk_gw_exception; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_exception
    ADD CONSTRAINT pk_gw_exception PRIMARY KEY (exception_time, device_id, type);


--
-- Name: gw_fire_wall pk_gw_fire_wall; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_fire_wall
    ADD CONSTRAINT pk_gw_fire_wall PRIMARY KEY (device_id);


--
-- Name: gw_ipmain pk_gw_ipmain; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_ipmain
    ADD CONSTRAINT pk_gw_ipmain PRIMARY KEY (subnet, inetmask);


--
-- Name: gw_iptv pk_gw_iptv; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_iptv
    ADD CONSTRAINT pk_gw_iptv PRIMARY KEY (device_id);


--
-- Name: gw_iptv_bbms pk_gw_iptv_bbms; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_iptv_bbms
    ADD CONSTRAINT pk_gw_iptv_bbms PRIMARY KEY (device_id);


--
-- Name: gw_lan_eth pk_gw_lan_eth; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_lan_eth
    ADD CONSTRAINT pk_gw_lan_eth PRIMARY KEY (device_id, lan_id, lan_eth_id);


--
-- Name: gw_lan_eth_history pk_gw_lan_eth_history; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_lan_eth_history
    ADD CONSTRAINT pk_gw_lan_eth_history PRIMARY KEY (device_id, lan_id, lan_eth_id);


--
-- Name: gw_lan_eth_namechange pk_gw_lan_eth_namechange; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_lan_eth_namechange
    ADD CONSTRAINT pk_gw_lan_eth_namechange PRIMARY KEY (device_id, lan_id, lan_eth_id);


--
-- Name: gw_lan_host pk_gw_lan_host; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_lan_host
    ADD CONSTRAINT pk_gw_lan_host PRIMARY KEY (device_id, host_inst, lan_inst);


--
-- Name: gw_lan_host_bbms pk_gw_lan_host_bbms; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_lan_host_bbms
    ADD CONSTRAINT pk_gw_lan_host_bbms PRIMARY KEY (device_id, host_inst, lan_inst);


--
-- Name: gw_lan_host_history pk_gw_lan_host_history; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_lan_host_history
    ADD CONSTRAINT pk_gw_lan_host_history PRIMARY KEY (device_id, host_inst, lan_inst);


--
-- Name: gw_lan_hostconf pk_gw_lan_hostconf; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_lan_hostconf
    ADD CONSTRAINT pk_gw_lan_hostconf PRIMARY KEY (device_id, lan_id);


--
-- Name: gw_lan_hostconf_bbms pk_gw_lan_hostconf_bbms; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_lan_hostconf_bbms
    ADD CONSTRAINT pk_gw_lan_hostconf_bbms PRIMARY KEY (device_id, lan_id);


--
-- Name: gw_lan_hostconf_history pk_gw_lan_hostconf_history; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_lan_hostconf_history
    ADD CONSTRAINT pk_gw_lan_hostconf_history PRIMARY KEY (device_id, lan_id);


--
-- Name: gw_lan_vlan_dhcp pk_gw_lan_vlan_dhcp; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_lan_vlan_dhcp
    ADD CONSTRAINT pk_gw_lan_vlan_dhcp PRIMARY KEY (device_id, vlan_i);


--
-- Name: gw_lan_vlan_num pk_gw_lan_vlan_num; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_lan_vlan_num
    ADD CONSTRAINT pk_gw_lan_vlan_num PRIMARY KEY (device_id);


--
-- Name: gw_lan_wlan pk_gw_lan_wlan; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_lan_wlan
    ADD CONSTRAINT pk_gw_lan_wlan PRIMARY KEY (device_id, lan_id, lan_wlan_id);


--
-- Name: gw_lan_wlan_bbms pk_gw_lan_wlan_bbms; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_lan_wlan_bbms
    ADD CONSTRAINT pk_gw_lan_wlan_bbms PRIMARY KEY (device_id, lan_id, lan_wlan_id);


--
-- Name: gw_lan_wlan_health pk_gw_lan_wlan_health; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_lan_wlan_health
    ADD CONSTRAINT pk_gw_lan_wlan_health PRIMARY KEY (device_id, lan_id, lan_wlan_id);


--
-- Name: gw_lan_wlan_history pk_gw_lan_wlan_history; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_lan_wlan_history
    ADD CONSTRAINT pk_gw_lan_wlan_history PRIMARY KEY (device_id, lan_id, lan_wlan_id, gather_time);


--
-- Name: gw_lan_wlan_namechange pk_gw_lan_wlan_namechange; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_lan_wlan_namechange
    ADD CONSTRAINT pk_gw_lan_wlan_namechange PRIMARY KEY (device_id, lan_id, lan_wlan_id);


--
-- Name: gw_mwband pk_gw_mwband; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_mwband
    ADD CONSTRAINT pk_gw_mwband PRIMARY KEY (device_id);


--
-- Name: gw_mwband_bbms pk_gw_mwband_bbms; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_mwband_bbms
    ADD CONSTRAINT pk_gw_mwband_bbms PRIMARY KEY (device_id);


--
-- Name: gw_office_voip pk_gw_office_voip; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_office_voip
    ADD CONSTRAINT pk_gw_office_voip PRIMARY KEY (office_id);


--
-- Name: gw_online_config pk_gw_online_config; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_online_config
    ADD CONSTRAINT pk_gw_online_config PRIMARY KEY (time_point, city_id);


--
-- Name: gw_online_report pk_gw_online_report; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_online_report
    ADD CONSTRAINT pk_gw_online_report PRIMARY KEY (city_id, r_timepoint);


--
-- Name: gw_order_type pk_gw_order_type; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_order_type
    ADD CONSTRAINT pk_gw_order_type PRIMARY KEY (type_id);


--
-- Name: gw_ping pk_gw_ping; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_ping
    ADD CONSTRAINT pk_gw_ping PRIMARY KEY (device_id, "time");


--
-- Name: gw_qos pk_gw_qos; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_qos
    ADD CONSTRAINT pk_gw_qos PRIMARY KEY (device_id);


--
-- Name: gw_qos_app pk_gw_qos_app; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_qos_app
    ADD CONSTRAINT pk_gw_qos_app PRIMARY KEY (device_id, app_id);


--
-- Name: gw_qos_app_bbms pk_gw_qos_app_bbms; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_qos_app_bbms
    ADD CONSTRAINT pk_gw_qos_app_bbms PRIMARY KEY (device_id, app_id);


--
-- Name: gw_qos_bbms pk_gw_qos_bbms; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_qos_bbms
    ADD CONSTRAINT pk_gw_qos_bbms PRIMARY KEY (device_id);


--
-- Name: gw_qos_class pk_gw_qos_class; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_qos_class
    ADD CONSTRAINT pk_gw_qos_class PRIMARY KEY (device_id, class_id);


--
-- Name: gw_qos_class_bbms pk_gw_qos_class_bbms; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_qos_class_bbms
    ADD CONSTRAINT pk_gw_qos_class_bbms PRIMARY KEY (device_id, class_id);


--
-- Name: gw_qos_class_type pk_gw_qos_class_type; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_qos_class_type
    ADD CONSTRAINT pk_gw_qos_class_type PRIMARY KEY (device_id, class_id, type_id);


--
-- Name: gw_qos_class_type_bbms pk_gw_qos_class_type_bbms; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_qos_class_type_bbms
    ADD CONSTRAINT pk_gw_qos_class_type_bbms PRIMARY KEY (device_id, class_id, type_id);


--
-- Name: gw_qos_queue pk_gw_qos_queue; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_qos_queue
    ADD CONSTRAINT pk_gw_qos_queue PRIMARY KEY (device_id, queue_id);


--
-- Name: gw_qos_queue_bbms pk_gw_qos_queue_bbms; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_qos_queue_bbms
    ADD CONSTRAINT pk_gw_qos_queue_bbms PRIMARY KEY (device_id, queue_id);


--
-- Name: gw_sec_access_control_bbms pk_gw_sec_access_control_bbms; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_sec_access_control_bbms
    ADD CONSTRAINT pk_gw_sec_access_control_bbms PRIMARY KEY (device_id);


--
-- Name: gw_sec_antivirus_bbms pk_gw_sec_antivirus_bbms; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_sec_antivirus_bbms
    ADD CONSTRAINT pk_gw_sec_antivirus_bbms PRIMARY KEY (device_id);


--
-- Name: gw_sec_content_filter_bbms pk_gw_sec_content_filter_bbms; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_sec_content_filter_bbms
    ADD CONSTRAINT pk_gw_sec_content_filter_bbms PRIMARY KEY (device_id);


--
-- Name: gw_sec_intrusion_detect_bbms pk_gw_sec_intrusion_detect_bbms; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_sec_intrusion_detect_bbms
    ADD CONSTRAINT pk_gw_sec_intrusion_detect_bbms PRIMARY KEY (device_id);


--
-- Name: gw_sec_mail_filter_bbms pk_gw_sec_mail_filter_bbms; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_sec_mail_filter_bbms
    ADD CONSTRAINT pk_gw_sec_mail_filter_bbms PRIMARY KEY (device_id);


--
-- Name: gw_serv_default pk_gw_serv_default; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_serv_default
    ADD CONSTRAINT pk_gw_serv_default PRIMARY KEY (serv_default_id);


--
-- Name: gw_serv_default_value pk_gw_serv_default_value; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_serv_default_value
    ADD CONSTRAINT pk_gw_serv_default_value PRIMARY KEY (serv_type_id, oper_type_id);


--
-- Name: gw_serv_package pk_gw_serv_package; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_serv_package
    ADD CONSTRAINT pk_gw_serv_package PRIMARY KEY (serv_package_id);


--
-- Name: gw_serv_package_type pk_gw_serv_package_type; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_serv_package_type
    ADD CONSTRAINT pk_gw_serv_package_type PRIMARY KEY (serv_package_id, serv_type_id);


--
-- Name: gw_serv_setloid pk_gw_serv_setloid; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_serv_setloid
    ADD CONSTRAINT pk_gw_serv_setloid PRIMARY KEY (task_id);


--
-- Name: gw_serv_strategy pk_gw_serv_strategy; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_serv_strategy
    ADD CONSTRAINT pk_gw_serv_strategy PRIMARY KEY (id);


--
-- Name: gw_serv_strategy_batch pk_gw_serv_strategy_batch; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_serv_strategy_batch
    ADD CONSTRAINT pk_gw_serv_strategy_batch PRIMARY KEY (id);


--
-- Name: gw_serv_strategy_log pk_gw_serv_strategy_log; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_serv_strategy_log
    ADD CONSTRAINT pk_gw_serv_strategy_log PRIMARY KEY (id);


--
-- Name: gw_serv_strategy_serv pk_gw_serv_strategy_serv; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_serv_strategy_serv
    ADD CONSTRAINT pk_gw_serv_strategy_serv PRIMARY KEY (id);


--
-- Name: gw_serv_strategy_serv_log pk_gw_serv_strategy_serv_log; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_serv_strategy_serv_log
    ADD CONSTRAINT pk_gw_serv_strategy_serv_log PRIMARY KEY (id);


--
-- Name: gw_serv_strategy_soft pk_gw_serv_strategy_soft; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_serv_strategy_soft
    ADD CONSTRAINT pk_gw_serv_strategy_soft PRIMARY KEY (id);


--
-- Name: gw_serv_strategy_soft_log pk_gw_serv_strategy_soft_log; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_serv_strategy_soft_log
    ADD CONSTRAINT pk_gw_serv_strategy_soft_log PRIMARY KEY (id);


--
-- Name: gw_serv_type_device_type pk_gw_serv_type_device_type; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_serv_type_device_type
    ADD CONSTRAINT pk_gw_serv_type_device_type PRIMARY KEY (serv_type_id, device_type);


--
-- Name: gw_setloid_device pk_gw_setloid_device; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_setloid_device
    ADD CONSTRAINT pk_gw_setloid_device PRIMARY KEY (task_id, device_id);


--
-- Name: gw_soft_upgrade_temp pk_gw_soft_upgrade_temp; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_soft_upgrade_temp
    ADD CONSTRAINT pk_gw_soft_upgrade_temp PRIMARY KEY (temp_id);


--
-- Name: gw_soft_upgrade_temp_map pk_gw_soft_upgrade_temp_map; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_soft_upgrade_temp_map
    ADD CONSTRAINT pk_gw_soft_upgrade_temp_map PRIMARY KEY (temp_id, devicetype_id_old);


--
-- Name: gw_strategy_qos pk_gw_strategy_qos; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_strategy_qos
    ADD CONSTRAINT pk_gw_strategy_qos PRIMARY KEY (id);


--
-- Name: gw_strategy_qos_param pk_gw_strategy_qos_param; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_strategy_qos_param
    ADD CONSTRAINT pk_gw_strategy_qos_param PRIMARY KEY (id, sub_order, type_order);


--
-- Name: gw_strategy_qos_tmpl pk_gw_strategy_qos_tmpl; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_strategy_qos_tmpl
    ADD CONSTRAINT pk_gw_strategy_qos_tmpl PRIMARY KEY (id);


--
-- Name: gw_strategy_sheet pk_gw_strategy_sheet; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_strategy_sheet
    ADD CONSTRAINT pk_gw_strategy_sheet PRIMARY KEY (id);


--
-- Name: gw_strategy_type pk_gw_strategy_type; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_strategy_type
    ADD CONSTRAINT pk_gw_strategy_type PRIMARY KEY (type_id);


--
-- Name: gw_subnets pk_gw_subnets; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_subnets
    ADD CONSTRAINT pk_gw_subnets PRIMARY KEY (id);


--
-- Name: gw_syslog_file pk_gw_syslog_file; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_syslog_file
    ADD CONSTRAINT pk_gw_syslog_file PRIMARY KEY (device_id, "time");


--
-- Name: gw_tr069 pk_gw_tr069; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_tr069
    ADD CONSTRAINT pk_gw_tr069 PRIMARY KEY (device_id);


--
-- Name: gw_tr069_bbms pk_gw_tr069_bbms; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_tr069_bbms
    ADD CONSTRAINT pk_gw_tr069_bbms PRIMARY KEY (device_id);


--
-- Name: gw_user_midware_serv pk_gw_user_midware_serv; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_user_midware_serv
    ADD CONSTRAINT pk_gw_user_midware_serv PRIMARY KEY (username, serv_type_id);


--
-- Name: gw_usertype_servtype pk_gw_usertype_servtype; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_usertype_servtype
    ADD CONSTRAINT pk_gw_usertype_servtype PRIMARY KEY (user_type);


--
-- Name: gw_version_file_path pk_gw_version_file_path; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_version_file_path
    ADD CONSTRAINT pk_gw_version_file_path PRIMARY KEY (id);


--
-- Name: gw_voip pk_gw_voip; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_voip
    ADD CONSTRAINT pk_gw_voip PRIMARY KEY (device_id, voip_id);


--
-- Name: gw_voip_bbms pk_gw_voip_bbms; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_voip_bbms
    ADD CONSTRAINT pk_gw_voip_bbms PRIMARY KEY (device_id, voip_id);


--
-- Name: gw_voip_digit_device pk_gw_voip_digit_device; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_voip_digit_device
    ADD CONSTRAINT pk_gw_voip_digit_device PRIMARY KEY (device_id, task_id, tasktime);


--
-- Name: gw_voip_digit_map pk_gw_voip_digit_map; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_voip_digit_map
    ADD CONSTRAINT pk_gw_voip_digit_map PRIMARY KEY (map_id);


--
-- Name: gw_voip_digit_task pk_gw_voip_digit_task; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_voip_digit_task
    ADD CONSTRAINT pk_gw_voip_digit_task PRIMARY KEY (task_id);


--
-- Name: gw_voip_init_param pk_gw_voip_init_param; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_voip_init_param
    ADD CONSTRAINT pk_gw_voip_init_param PRIMARY KEY (device_id);


--
-- Name: gw_voip_prof pk_gw_voip_prof; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_voip_prof
    ADD CONSTRAINT pk_gw_voip_prof PRIMARY KEY (device_id, voip_id, prof_id);


--
-- Name: gw_voip_prof_bbms pk_gw_voip_prof_bbms; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_voip_prof_bbms
    ADD CONSTRAINT pk_gw_voip_prof_bbms PRIMARY KEY (device_id, voip_id, prof_id);


--
-- Name: gw_voip_prof_h248 pk_gw_voip_prof_h248; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_voip_prof_h248
    ADD CONSTRAINT pk_gw_voip_prof_h248 PRIMARY KEY (device_id, voip_id, prof_id);


--
-- Name: gw_voip_prof_h248_bbms pk_gw_voip_prof_h248_bbms; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_voip_prof_h248_bbms
    ADD CONSTRAINT pk_gw_voip_prof_h248_bbms PRIMARY KEY (device_id, voip_id, prof_id);


--
-- Name: gw_voip_prof_line pk_gw_voip_prof_line; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_voip_prof_line
    ADD CONSTRAINT pk_gw_voip_prof_line PRIMARY KEY (device_id, voip_id, prof_id, line_id);


--
-- Name: gw_voip_prof_line_bbms pk_gw_voip_prof_line_bbms; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_voip_prof_line_bbms
    ADD CONSTRAINT pk_gw_voip_prof_line_bbms PRIMARY KEY (device_id, voip_id, prof_id, line_id);


--
-- Name: gw_wan pk_gw_wan; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_wan
    ADD CONSTRAINT pk_gw_wan PRIMARY KEY (device_id, wan_id);


--
-- Name: gw_wan_bbms pk_gw_wan_bbms; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_wan_bbms
    ADD CONSTRAINT pk_gw_wan_bbms PRIMARY KEY (device_id, wan_id);


--
-- Name: gw_wan_conn pk_gw_wan_conn; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_wan_conn
    ADD CONSTRAINT pk_gw_wan_conn PRIMARY KEY (device_id, wan_id, wan_conn_id);


--
-- Name: gw_wan_conn_bbms pk_gw_wan_conn_bbms; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_wan_conn_bbms
    ADD CONSTRAINT pk_gw_wan_conn_bbms PRIMARY KEY (device_id, wan_id, wan_conn_id);


--
-- Name: gw_wan_conn_history pk_gw_wan_conn_history; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_wan_conn_history
    ADD CONSTRAINT pk_gw_wan_conn_history PRIMARY KEY (device_id, wan_id, wan_conn_id, gather_time);


--
-- Name: gw_wan_conn_namechange pk_gw_wan_conn_namechange; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_wan_conn_namechange
    ADD CONSTRAINT pk_gw_wan_conn_namechange PRIMARY KEY (device_id, wan_id, wan_conn_id);


--
-- Name: gw_wan_conn_session pk_gw_wan_conn_session; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_wan_conn_session
    ADD CONSTRAINT pk_gw_wan_conn_session PRIMARY KEY (device_id, wan_id, wan_conn_id, wan_conn_sess_id, sess_type);


--
-- Name: gw_wan_conn_session_bbms pk_gw_wan_conn_session_bbms; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_wan_conn_session_bbms
    ADD CONSTRAINT pk_gw_wan_conn_session_bbms PRIMARY KEY (device_id, wan_id, wan_conn_id, wan_conn_sess_id, sess_type, gather_time);


--
-- Name: gw_wan_conn_session_history pk_gw_wan_conn_session_history; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_wan_conn_session_history
    ADD CONSTRAINT pk_gw_wan_conn_session_history PRIMARY KEY (device_id, wan_id, wan_conn_id, wan_conn_sess_id, sess_type, gather_time);


--
-- Name: gw_wan_conn_session_namechange pk_gw_wan_conn_session_namechange; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_wan_conn_session_namechange
    ADD CONSTRAINT pk_gw_wan_conn_session_namechange PRIMARY KEY (device_id, wan_id, wan_conn_id, wan_conn_sess_id, sess_type);


--
-- Name: gw_wan_conn_session_vpn_bbms pk_gw_wan_conn_session_vpn_bbms; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_wan_conn_session_vpn_bbms
    ADD CONSTRAINT pk_gw_wan_conn_session_vpn_bbms PRIMARY KEY (device_id, wan_id, wan_conn_id, wan_conn_sess_id, sess_type, wan_conn_sess_vpn_id);


--
-- Name: gw_wan_dsl_inter_conf_health pk_gw_wan_dsl_inter_conf_health; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_wan_dsl_inter_conf_health
    ADD CONSTRAINT pk_gw_wan_dsl_inter_conf_health PRIMARY KEY (device_id, wan_id);


--
-- Name: gw_wan_history pk_gw_wan_history; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_wan_history
    ADD CONSTRAINT pk_gw_wan_history PRIMARY KEY (device_id, wan_id);


--
-- Name: gw_wan_namechange pk_gw_wan_namechange; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_wan_namechange
    ADD CONSTRAINT pk_gw_wan_namechange PRIMARY KEY (device_id, wan_id);


--
-- Name: gw_wan_wireinfo pk_gw_wan_wireinfo; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_wan_wireinfo
    ADD CONSTRAINT pk_gw_wan_wireinfo PRIMARY KEY (device_id, wan_id);


--
-- Name: gw_wan_wireinfo_bbms pk_gw_wan_wireinfo_bbms; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_wan_wireinfo_bbms
    ADD CONSTRAINT pk_gw_wan_wireinfo_bbms PRIMARY KEY (device_id, wan_id);


--
-- Name: gw_wan_wireinfo_epon pk_gw_wan_wireinfo_epon; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_wan_wireinfo_epon
    ADD CONSTRAINT pk_gw_wan_wireinfo_epon PRIMARY KEY (device_id, wan_id);


--
-- Name: gw_wan_wireinfo_epon_bbms pk_gw_wan_wireinfo_epon_bbms; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_wan_wireinfo_epon_bbms
    ADD CONSTRAINT pk_gw_wan_wireinfo_epon_bbms PRIMARY KEY (device_id, wan_id);


--
-- Name: gw_wan_wireinfo_epon_history pk_gw_wan_wireinfo_epon_history; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_wan_wireinfo_epon_history
    ADD CONSTRAINT pk_gw_wan_wireinfo_epon_history PRIMARY KEY (device_id, wan_id, gather_time);


--
-- Name: gw_wlan_asso pk_gw_wlan_asso; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_wlan_asso
    ADD CONSTRAINT pk_gw_wlan_asso PRIMARY KEY (device_id, lan_id, lan_wlan_id, asso_id);


--
-- Name: gw_wlan_asso_bbms pk_gw_wlan_asso_bbms; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.gw_wlan_asso_bbms
    ADD CONSTRAINT pk_gw_wlan_asso_bbms PRIMARY KEY (device_id, lan_id, lan_wlan_id, asso_id);


--
-- Name: hgw_item_role pk_hgw_item_role; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.hgw_item_role
    ADD CONSTRAINT pk_hgw_item_role PRIMARY KEY (item_id, role_id);


--
-- Name: itms_bssuser_info pk_itms_bssuser_info; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.itms_bssuser_info
    ADD CONSTRAINT pk_itms_bssuser_info PRIMARY KEY (user_id);


--
-- Name: tab_alarm_record pk_tab_alarm_record_id_id; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_alarm_record
    ADD CONSTRAINT pk_tab_alarm_record_id_id PRIMARY KEY (id);


--
-- Name: tab_app_sign_config pk_tab_app_sign_config_id_id; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_app_sign_config
    ADD CONSTRAINT pk_tab_app_sign_config_id_id PRIMARY KEY (id);


--
-- Name: tab_attach_devlist pk_tab_attach_devlist_id; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_attach_devlist
    ADD CONSTRAINT pk_tab_attach_devlist_id PRIMARY KEY (id);


--
-- Name: tab_city pk_tab_city; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_city
    ADD CONSTRAINT pk_tab_city PRIMARY KEY (city_id);


--
-- Name: tab_city_area pk_tab_city_area; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_city_area
    ADD CONSTRAINT pk_tab_city_area PRIMARY KEY (city_id);


--
-- Name: tab_city_code pk_tab_city_code; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_city_code
    ADD CONSTRAINT pk_tab_city_code PRIMARY KEY (city_id);


--
-- Name: tab_cmd pk_tab_cmd; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_cmd
    ADD CONSTRAINT pk_tab_cmd PRIMARY KEY (rpc_id);


--
-- Name: tab_conf_node pk_tab_conf_node; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_conf_node
    ADD CONSTRAINT pk_tab_conf_node PRIMARY KEY (node_id);


--
-- Name: tab_cpe_classify_statistic pk_tab_cpe_classify_statistic; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_cpe_classify_statistic
    ADD CONSTRAINT pk_tab_cpe_classify_statistic PRIMARY KEY (id);


--
-- Name: tab_cpe_faultcode pk_tab_cpe_faultcode; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_cpe_faultcode
    ADD CONSTRAINT pk_tab_cpe_faultcode PRIMARY KEY (fault_code);


--
-- Name: tab_customer_ftth pk_tab_customer_ftth; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_customer_ftth
    ADD CONSTRAINT pk_tab_customer_ftth PRIMARY KEY (user_id);


--
-- Name: tab_customerinfo pk_tab_customerinfo; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_customerinfo
    ADD CONSTRAINT pk_tab_customerinfo PRIMARY KEY (customer_id);


--
-- Name: tab_dev_batch_restart pk_tab_dev_batch_restart; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_dev_batch_restart
    ADD CONSTRAINT pk_tab_dev_batch_restart PRIMARY KEY (task_id);


--
-- Name: tab_dev_black pk_tab_dev_black; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_dev_black
    ADD CONSTRAINT pk_tab_dev_black PRIMARY KEY (device_id);


--
-- Name: tab_dev_stack_info pk_tab_dev_stack_info; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_dev_stack_info
    ADD CONSTRAINT pk_tab_dev_stack_info PRIMARY KEY (device_id, serv_type_id);


--
-- Name: tab_device_version_attribute pk_tab_device_version_attribute; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_device_version_attribute
    ADD CONSTRAINT pk_tab_device_version_attribute PRIMARY KEY (devicetype_id);


--
-- Name: tab_devicefault pk_tab_devicefault; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_devicefault
    ADD CONSTRAINT pk_tab_devicefault PRIMARY KEY (device_id, faulttime);


--
-- Name: tab_devicemodel_template pk_tab_devicemodel_template; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_devicemodel_template
    ADD CONSTRAINT pk_tab_devicemodel_template PRIMARY KEY (device_model_id);


--
-- Name: tab_devicetype_info pk_tab_devicetype_info; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_devicetype_info
    ADD CONSTRAINT pk_tab_devicetype_info PRIMARY KEY (devicetype_id);


--
-- Name: tab_devicetype_info_port pk_tab_devicetype_info_port; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_devicetype_info_port
    ADD CONSTRAINT pk_tab_devicetype_info_port PRIMARY KEY (devicetype_id, port_dir);


--
-- Name: tab_devicetype_info_servertype pk_tab_devicetype_info_servertype; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_devicetype_info_servertype
    ADD CONSTRAINT pk_tab_devicetype_info_servertype PRIMARY KEY (devicetype_id, server_type);


--
-- Name: tab_digit_map pk_tab_digit_map; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_digit_map
    ADD CONSTRAINT pk_tab_digit_map PRIMARY KEY (digit_map_code);


--
-- Name: tab_egw_bsn_open_original pk_tab_egw_bsn_open_original; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_egw_bsn_open_original
    ADD CONSTRAINT pk_tab_egw_bsn_open_original PRIMARY KEY (id);


--
-- Name: tab_egw_net_serv_param pk_tab_egw_net_serv_param; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_egw_net_serv_param
    ADD CONSTRAINT pk_tab_egw_net_serv_param PRIMARY KEY (user_id, username);


--
-- Name: tab_egw_voip_serv_param pk_tab_egw_voip_serv_param; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_egw_voip_serv_param
    ADD CONSTRAINT pk_tab_egw_voip_serv_param PRIMARY KEY (user_id, line_id);


--
-- Name: tab_egwcustomer pk_tab_egwcustomer; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_egwcustomer
    ADD CONSTRAINT pk_tab_egwcustomer PRIMARY KEY (user_id);


--
-- Name: tab_excel_syn_accounts pk_tab_excel_syn_accounts; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_excel_syn_accounts
    ADD CONSTRAINT pk_tab_excel_syn_accounts PRIMARY KEY (enname);


--
-- Name: tab_file_server pk_tab_file_server; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_file_server
    ADD CONSTRAINT pk_tab_file_server PRIMARY KEY (dir_id);


--
-- Name: tab_fttr_master_slave pk_tab_fttr_master_slave; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_fttr_master_slave
    ADD CONSTRAINT pk_tab_fttr_master_slave PRIMARY KEY (master_device_id);


--
-- Name: tab_group pk_tab_group; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_group
    ADD CONSTRAINT pk_tab_group PRIMARY KEY (group_oid);


--
-- Name: tab_gw_card pk_tab_gw_card; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_gw_card
    ADD CONSTRAINT pk_tab_gw_card PRIMARY KEY (card_id);


--
-- Name: tab_gw_device_init pk_tab_gw_device_init; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_gw_device_init
    ADD CONSTRAINT pk_tab_gw_device_init PRIMARY KEY (device_id);


--
-- Name: tab_gw_device_init_oui pk_tab_gw_device_init_oui; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_gw_device_init_oui
    ADD CONSTRAINT pk_tab_gw_device_init_oui PRIMARY KEY (id);


--
-- Name: tab_gw_device_refuse pk_tab_gw_device_refuse; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_gw_device_refuse
    ADD CONSTRAINT pk_tab_gw_device_refuse PRIMARY KEY (oui, device_serialnumber);


--
-- Name: tab_gw_device_stbmac pk_tab_gw_device_stbmac; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_gw_device_stbmac
    ADD CONSTRAINT pk_tab_gw_device_stbmac PRIMARY KEY (device_id, stb_mac, lan_port);


--
-- Name: tab_gw_identity pk_tab_gw_identity; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_gw_identity
    ADD CONSTRAINT pk_tab_gw_identity PRIMARY KEY (res_type);


--
-- Name: tab_gw_identity_bak pk_tab_gw_identity_bak; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_gw_identity_bak
    ADD CONSTRAINT pk_tab_gw_identity_bak PRIMARY KEY (res_type);


--
-- Name: tab_gw_oper_type pk_tab_gw_oper_type; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_gw_oper_type
    ADD CONSTRAINT pk_tab_gw_oper_type PRIMARY KEY (oper_type_id);


--
-- Name: tab_gw_res_area pk_tab_gw_res_area; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_gw_res_area
    ADD CONSTRAINT pk_tab_gw_res_area PRIMARY KEY (res_type, res_id, area_id);


--
-- Name: tab_gw_serv_type pk_tab_gw_serv_type; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_gw_serv_type
    ADD CONSTRAINT pk_tab_gw_serv_type PRIMARY KEY (serv_type_id);


--
-- Name: tab_gw_stbid pk_tab_gw_stbid; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_gw_stbid
    ADD CONSTRAINT pk_tab_gw_stbid PRIMARY KEY (device_id);


--
-- Name: tab_hgwcustomer pk_tab_hgwcustomer; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_hgwcustomer
    ADD CONSTRAINT pk_tab_hgwcustomer PRIMARY KEY (user_id);


--
-- Name: tab_hgwcustomer_bak pk_tab_hgwcustomer_bak; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_hgwcustomer_bak
    ADD CONSTRAINT pk_tab_hgwcustomer_bak PRIMARY KEY (user_id);


--
-- Name: tab_hqs_serv_param pk_tab_hqs_serv_param; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_hqs_serv_param
    ADD CONSTRAINT pk_tab_hqs_serv_param PRIMARY KEY (user_id, serv_type_id);


--
-- Name: tab_http_test_user pk_tab_http_test_user; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_http_test_user
    ADD CONSTRAINT pk_tab_http_test_user PRIMARY KEY (testname);


--
-- Name: tab_ior pk_tab_ior; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_ior
    ADD CONSTRAINT pk_tab_ior PRIMARY KEY (object_name, object_poa);


--
-- Name: tab_ipsec_serv_param pk_tab_ipsec_serv_param; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_ipsec_serv_param
    ADD CONSTRAINT pk_tab_ipsec_serv_param PRIMARY KEY (user_id, username, serv_type_id);


--
-- Name: tab_iptv_serv_param pk_tab_iptv_serv_param; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_iptv_serv_param
    ADD CONSTRAINT pk_tab_iptv_serv_param PRIMARY KEY (user_id);


--
-- Name: tab_iptv_user pk_tab_iptv_user; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_iptv_user
    ADD CONSTRAINT pk_tab_iptv_user PRIMARY KEY (user_id, serv_type_id);


--
-- Name: tab_item pk_tab_item; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_item
    ADD CONSTRAINT pk_tab_item PRIMARY KEY (item_id);


--
-- Name: tab_item_role pk_tab_item_role; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_item_role
    ADD CONSTRAINT pk_tab_item_role PRIMARY KEY (item_id, role_id);


--
-- Name: tab_modify_vlan_task pk_tab_modify_vlan_task; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_modify_vlan_task
    ADD CONSTRAINT pk_tab_modify_vlan_task PRIMARY KEY (task_id);


--
-- Name: tab_monthgather_device pk_tab_monthgather_device; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_monthgather_device
    ADD CONSTRAINT pk_tab_monthgather_device PRIMARY KEY (device_id, username);


--
-- Name: tab_monthgather_device_manual pk_tab_monthgather_device_manual; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_monthgather_device_manual
    ADD CONSTRAINT pk_tab_monthgather_device_manual PRIMARY KEY (device_id);


--
-- Name: tab_netacc_spead pk_tab_netacc_spead; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_netacc_spead
    ADD CONSTRAINT pk_tab_netacc_spead PRIMARY KEY (username);


--
-- Name: tab_office pk_tab_office; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_office
    ADD CONSTRAINT pk_tab_office PRIMARY KEY (office_id);


--
-- Name: tab_oss_dslperformance pk_tab_oss_dslperformance; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_oss_dslperformance
    ADD CONSTRAINT pk_tab_oss_dslperformance PRIMARY KEY (device_id);


--
-- Name: tab_oss_wifiassociatedinfo pk_tab_oss_wifiassociatedinfo; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_oss_wifiassociatedinfo
    ADD CONSTRAINT pk_tab_oss_wifiassociatedinfo PRIMARY KEY (device_id, landevice_j, associateddevice_k);


--
-- Name: tab_oss_wifissidinfo pk_tab_oss_wifissidinfo; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_oss_wifissidinfo
    ADD CONSTRAINT pk_tab_oss_wifissidinfo PRIMARY KEY (device_id, landevice_j);


--
-- Name: tab_para pk_tab_para; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_para
    ADD CONSTRAINT pk_tab_para PRIMARY KEY (para_id);


--
-- Name: tab_para_type pk_tab_para_type; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_para_type
    ADD CONSTRAINT pk_tab_para_type PRIMARY KEY (para_type_id);


--
-- Name: tab_performance_alarm pk_tab_performance_alarm; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_performance_alarm
    ADD CONSTRAINT pk_tab_performance_alarm PRIMARY KEY (id);


--
-- Name: tab_performance_mangement pk_tab_performance_mangement; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_performance_mangement
    ADD CONSTRAINT pk_tab_performance_mangement PRIMARY KEY (id);


--
-- Name: tab_permission_collect pk_tab_permission_collect; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_permission_collect
    ADD CONSTRAINT pk_tab_permission_collect PRIMARY KEY (id);


--
-- Name: tab_persons pk_tab_persons; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_persons
    ADD CONSTRAINT pk_tab_persons PRIMARY KEY (per_acc_oid);


--
-- Name: tab_process pk_tab_process; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_process
    ADD CONSTRAINT pk_tab_process PRIMARY KEY (gather_id, process_name);


--
-- Name: tab_process_config pk_tab_process_config; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_process_config
    ADD CONSTRAINT pk_tab_process_config PRIMARY KEY (gather_id, process_name, location, para_item);


--
-- Name: tab_process_desc pk_tab_process_desc; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_process_desc
    ADD CONSTRAINT pk_tab_process_desc PRIMARY KEY (gather_id);


--
-- Name: tab_register_cpe_origin pk_tab_register_cpe_origin; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_register_cpe_origin
    ADD CONSTRAINT pk_tab_register_cpe_origin PRIMARY KEY (id);


--
-- Name: tab_register_serv_origin pk_tab_register_serv_origin; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_register_serv_origin
    ADD CONSTRAINT pk_tab_register_serv_origin PRIMARY KEY (id);


--
-- Name: tab_register_task pk_tab_register_task; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_register_task
    ADD CONSTRAINT pk_tab_register_task PRIMARY KEY (task_id);


--
-- Name: tab_role pk_tab_role; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_role
    ADD CONSTRAINT pk_tab_role PRIMARY KEY (role_id);


--
-- Name: tab_rpc_match pk_tab_rpc_match; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_rpc_match
    ADD CONSTRAINT pk_tab_rpc_match PRIMARY KEY (tc_serial, name, flag);


--
-- Name: tab_serv_classify_statistic pk_tab_serv_classify_statistic; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_serv_classify_statistic
    ADD CONSTRAINT pk_tab_serv_classify_statistic PRIMARY KEY (id);


--
-- Name: tab_serv_template pk_tab_serv_template; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_serv_template
    ADD CONSTRAINT pk_tab_serv_template PRIMARY KEY (id);


--
-- Name: tab_service pk_tab_service; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_service
    ADD CONSTRAINT pk_tab_service PRIMARY KEY (service_id, wan_type);


--
-- Name: tab_service_sub pk_tab_service_sub; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_service_sub
    ADD CONSTRAINT pk_tab_service_sub PRIMARY KEY (sub_service_id);


--
-- Name: tab_servicecode pk_tab_servicecode; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_servicecode
    ADD CONSTRAINT pk_tab_servicecode PRIMARY KEY (servicecode);


--
-- Name: tab_setmulticast_task pk_tab_setmulticast_task; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_setmulticast_task
    ADD CONSTRAINT pk_tab_setmulticast_task PRIMARY KEY (task_id);


--
-- Name: tab_sheet pk_tab_sheet; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_sheet
    ADD CONSTRAINT pk_tab_sheet PRIMARY KEY (sheet_id);


--
-- Name: tab_sheet_auth pk_tab_sheet_auth; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_sheet_auth
    ADD CONSTRAINT pk_tab_sheet_auth PRIMARY KEY (auth_id);


--
-- Name: tab_sheet_cmd pk_tab_sheet_cmd; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_sheet_cmd
    ADD CONSTRAINT pk_tab_sheet_cmd PRIMARY KEY (sheet_id, rpc_order);


--
-- Name: tab_sheet_para_value pk_tab_sheet_para_value; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_sheet_para_value
    ADD CONSTRAINT pk_tab_sheet_para_value PRIMARY KEY (id);


--
-- Name: tab_sheet_report pk_tab_sheet_report; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_sheet_report
    ADD CONSTRAINT pk_tab_sheet_report PRIMARY KEY (sheet_id, receive_time);


--
-- Name: tab_sip_info pk_tab_sip_info; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_sip_info
    ADD CONSTRAINT pk_tab_sip_info PRIMARY KEY (sip_id);


--
-- Name: tab_soft_upgrade_record pk_tab_soft_upgrade_record; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_soft_upgrade_record
    ADD CONSTRAINT pk_tab_soft_upgrade_record PRIMARY KEY (record_id);


--
-- Name: tab_speed_net pk_tab_speed_net; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_speed_net
    ADD CONSTRAINT pk_tab_speed_net PRIMARY KEY (test_rate, city_id);


--
-- Name: tab_stack_task pk_tab_stack_task; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_stack_task
    ADD CONSTRAINT pk_tab_stack_task PRIMARY KEY (task_id);


--
-- Name: tab_static_src pk_tab_static_src; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_static_src
    ADD CONSTRAINT pk_tab_static_src PRIMARY KEY (src_type, src_code);


--
-- Name: tab_summary_data pk_tab_summary_data; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_summary_data
    ADD CONSTRAINT pk_tab_summary_data PRIMARY KEY (device_id);


--
-- Name: tab_template pk_tab_template; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_template
    ADD CONSTRAINT pk_tab_template PRIMARY KEY (template_id);


--
-- Name: tab_template_cmd pk_tab_template_cmd; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_template_cmd
    ADD CONSTRAINT pk_tab_template_cmd PRIMARY KEY (template_id, rpc_id, rpc_order);


--
-- Name: tab_template_cmd_para pk_tab_template_cmd_para; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_template_cmd_para
    ADD CONSTRAINT pk_tab_template_cmd_para PRIMARY KEY (tc_serial, para_serial);


--
-- Name: tab_tree_item pk_tab_tree_item; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_tree_item
    ADD CONSTRAINT pk_tab_tree_item PRIMARY KEY (tree_id, item_id);


--
-- Name: tab_tree_role pk_tab_tree_role; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_tree_role
    ADD CONSTRAINT pk_tab_tree_role PRIMARY KEY (tree_id, role_id);


--
-- Name: tab_tt_alarm pk_tab_tt_alarm; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_tt_alarm
    ADD CONSTRAINT pk_tab_tt_alarm PRIMARY KEY (device_id);


--
-- Name: tab_tt_alarm_fail pk_tab_tt_alarm_fail; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_tt_alarm_fail
    ADD CONSTRAINT pk_tab_tt_alarm_fail PRIMARY KEY (id);


--
-- Name: tab_upload_log_file_info pk_tab_upload_log_file_info; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_upload_log_file_info
    ADD CONSTRAINT pk_tab_upload_log_file_info PRIMARY KEY (device_id);


--
-- Name: tab_vendor pk_tab_vendor; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_vendor
    ADD CONSTRAINT pk_tab_vendor PRIMARY KEY (vendor_id);


--
-- Name: tab_vendor_oui pk_tab_vendor_oui; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_vendor_oui
    ADD CONSTRAINT pk_tab_vendor_oui PRIMARY KEY (vendor_id, oui);


--
-- Name: tab_vercon_file pk_tab_vercon_file; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_vercon_file
    ADD CONSTRAINT pk_tab_vercon_file PRIMARY KEY (verconfile_id);


--
-- Name: tab_voice_ping_param pk_tab_voice_ping_param; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_voice_ping_param
    ADD CONSTRAINT pk_tab_voice_ping_param PRIMARY KEY (id);


--
-- Name: tab_voip_serv_param pk_tab_voip_serv_param; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_voip_serv_param
    ADD CONSTRAINT pk_tab_voip_serv_param PRIMARY KEY (user_id, line_id);


--
-- Name: tab_vxlan_forwarding_config pk_tab_vxlan_forwarding_config; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_vxlan_forwarding_config
    ADD CONSTRAINT pk_tab_vxlan_forwarding_config PRIMARY KEY (user_id, next_hop, des_ip);


--
-- Name: tab_vxlan_nat_config pk_tab_vxlan_nat_config; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_vxlan_nat_config
    ADD CONSTRAINT pk_tab_vxlan_nat_config PRIMARY KEY (user_id, pub_ipv4);


--
-- Name: tab_vxlan_serv_param pk_tab_vxlan_serv_param; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_vxlan_serv_param
    ADD CONSTRAINT pk_tab_vxlan_serv_param PRIMARY KEY (user_id, serv_type_id, username, vxlanconfigsequence);


--
-- Name: tab_whitelist_dev pk_tab_whitelist_dev; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_whitelist_dev
    ADD CONSTRAINT pk_tab_whitelist_dev PRIMARY KEY (device_id, task_type);


--
-- Name: tab_wirelesst_task pk_tab_wirelesst_task; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_wirelesst_task
    ADD CONSTRAINT pk_tab_wirelesst_task PRIMARY KEY (task_id);


--
-- Name: tab_zeroconfig_report pk_tab_zeroconfig_report; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_zeroconfig_report
    ADD CONSTRAINT pk_tab_zeroconfig_report PRIMARY KEY (cmdid);


--
-- Name: tab_zone pk_tab_zone; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_zone
    ADD CONSTRAINT pk_tab_zone PRIMARY KEY (zone_id);


--
-- Name: user_type pk_user_type; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.user_type
    ADD CONSTRAINT pk_user_type PRIMARY KEY (user_type_id);


--
-- Name: stb_gw_devicestatus stb_gw_devicestatus_pkey; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.stb_gw_devicestatus
    ADD CONSTRAINT stb_gw_devicestatus_pkey PRIMARY KEY (device_id);


--
-- Name: stb_gw_serv_strategy_batch_log stb_gw_serv_strategy_batch_log_pkey; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.stb_gw_serv_strategy_batch_log
    ADD CONSTRAINT stb_gw_serv_strategy_batch_log_pkey PRIMARY KEY (id);


--
-- Name: stb_gw_serv_strategy_batch stb_gw_serv_strategy_batch_pkey; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.stb_gw_serv_strategy_batch
    ADD CONSTRAINT stb_gw_serv_strategy_batch_pkey PRIMARY KEY (id);


--
-- Name: stb_gw_serv_strategy_log stb_gw_serv_strategy_log_pkey; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.stb_gw_serv_strategy_log
    ADD CONSTRAINT stb_gw_serv_strategy_log_pkey PRIMARY KEY (id);


--
-- Name: stb_gw_serv_strategy stb_gw_serv_strategy_pkey; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.stb_gw_serv_strategy
    ADD CONSTRAINT stb_gw_serv_strategy_pkey PRIMARY KEY (id);


--
-- Name: stb_tab_gw_device stb_tab_gw_device_pkey; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.stb_tab_gw_device
    ADD CONSTRAINT stb_tab_gw_device_pkey PRIMARY KEY (device_id);


--
-- Name: tab_capacity_log_parameter_bak_20260324121914 tab_capacity_log_parameter_pkey; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_capacity_log_parameter_bak_20260324121914
    ADD CONSTRAINT tab_capacity_log_parameter_pkey PRIMARY KEY (call_id);


--
-- Name: tab_dev_group tab_dev_group_pkey; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_dev_group
    ADD CONSTRAINT tab_dev_group_pkey PRIMARY KEY (group_id);


--
-- Name: tab_device_bandwidth_rule tab_device_bindwidth_rule_pkey; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_device_bandwidth_rule
    ADD CONSTRAINT tab_device_bindwidth_rule_pkey PRIMARY KEY (id);


--
-- Name: tab_gw_device tab_gw_device_pkey; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_gw_device
    ADD CONSTRAINT tab_gw_device_pkey PRIMARY KEY (device_id);


--
-- Name: tab_http_telnet_switch_record tab_http_telnet_switch_record_pkey; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_http_telnet_switch_record
    ADD CONSTRAINT tab_http_telnet_switch_record_pkey PRIMARY KEY (id);


--
-- Name: tab_quality_issue_analysis_detail tab_quality_issue_analysis_detail_pkey; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_quality_issue_analysis_detail
    ADD CONSTRAINT tab_quality_issue_analysis_detail_pkey PRIMARY KEY (id);


--
-- Name: tab_quality_issue_analysis tab_quality_issue_analysis_pkey; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_quality_issue_analysis
    ADD CONSTRAINT tab_quality_issue_analysis_pkey PRIMARY KEY (id);


--
-- Name: tab_quality_issue_fixed_history tab_quality_issue_fixed_history_pkey; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_quality_issue_fixed_history
    ADD CONSTRAINT tab_quality_issue_fixed_history_pkey PRIMARY KEY (id);


--
-- Name: tab_quality_issue_kpi_rule tab_quality_issue_kpi_rule_pkey; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_quality_issue_kpi_rule
    ADD CONSTRAINT tab_quality_issue_kpi_rule_pkey PRIMARY KEY (id);


--
-- Name: tab_quality_issue_repair_his tab_quality_issue_repair_his_pkey; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_quality_issue_repair_his
    ADD CONSTRAINT tab_quality_issue_repair_his_pkey PRIMARY KEY (id);


--
-- Name: tab_quality_issue_suggestion tab_quality_issue_suggestion_pk; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_quality_issue_suggestion
    ADD CONSTRAINT tab_quality_issue_suggestion_pk PRIMARY KEY (id);


--
-- Name: tab_software_file tab_software_file_pkey; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_software_file
    ADD CONSTRAINT tab_software_file_pkey PRIMARY KEY (softwarefile_id);


--
-- Name: tab_ux_inform_log_bak_20260324121914 tab_ux_inform_log_pkey; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_ux_inform_log_bak_20260324121914
    ADD CONSTRAINT tab_ux_inform_log_pkey PRIMARY KEY (id);


--
-- Name: tab_vendor_ieee tab_vendor_ieee_pkey; Type: CONSTRAINT; Schema: public; Owner: gtmsmanager
--

ALTER TABLE ONLY public.tab_vendor_ieee
    ADD CONSTRAINT tab_vendor_ieee_pkey PRIMARY KEY (vendor_id);


--
-- Name: bss_sheet_bak_username; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX bss_sheet_bak_username ON public.tab_bss_sheet_bak USING btree (username);


--
-- Name: bss_sheet_username; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX bss_sheet_username ON public.tab_bss_sheet USING btree (username);


--
-- Name: dev_complete_time; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX dev_complete_time ON public.tab_gw_device USING btree (complete_time);


--
-- Name: dev_stb_complete_time; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX dev_stb_complete_time ON public.stb_tab_gw_device USING btree (complete_time);


--
-- Name: device_dev_ip; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX device_dev_ip ON public.tab_gw_device USING btree (loopback_ip);


--
-- Name: device_stb_dev_ip; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX device_stb_dev_ip ON public.stb_tab_gw_device USING btree (loopback_ip);


--
-- Name: egwcustomer_dev_id; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX egwcustomer_dev_id ON public.tab_egwcustomer USING btree (device_id);


--
-- Name: f_dev_model_type_o_type_id; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX f_dev_model_type_o_type_id ON public.gw_dev_model_dev_type USING btree (type_id);


--
-- Name: f_gw_stra_qos_tmpl_o_tmpl_id; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX f_gw_stra_qos_tmpl_o_tmpl_id ON public.gw_strategy_qos_tmpl USING btree (tmpl_id);


--
-- Name: f_itv_cust_info_o_pack_id; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX f_itv_cust_info_o_pack_id ON public.itv_customer_info USING btree (serv_package_id);


--
-- Name: f_itv_cust_info_o_spec_id; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX f_itv_cust_info_o_spec_id ON public.itv_customer_info USING btree (prod_spec_id);


--
-- Name: f_itv_cust_info_o_type_id; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX f_itv_cust_info_o_type_id ON public.itv_customer_info USING btree (type_id);


--
-- Name: f_user_dev_type_o_type_id; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX f_user_dev_type_o_type_id ON public.gw_cust_user_dev_type USING btree (type_id);


--
-- Name: f_user_pack_o_pack_id; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX f_user_pack_o_pack_id ON public.gw_cust_user_package USING btree (serv_package_id);


--
-- Name: f_user_pack_o_pack_id1; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX f_user_pack_o_pack_id1 ON public.gw_cust_user_package_copy1 USING btree (serv_package_id);


--
-- Name: hgwcustomer_username; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX hgwcustomer_username ON public.tab_hgwcustomer USING btree (username);


--
-- Name: i_bak_prod_spec_id; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX i_bak_prod_spec_id ON public.tab_bss_sheet_bak USING btree (product_spec_id);


--
-- Name: i_binddate; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX i_binddate ON public.tab_hgwcustomer USING btree (binddate);


--
-- Name: i_bindfail_devid; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX i_bindfail_devid ON public.tab_bind_fail USING btree (device_id);


--
-- Name: i_bindfail_loid; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX i_bindfail_loid ON public.tab_bind_fail USING btree (username);


--
-- Name: i_bss_sheet_id; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX i_bss_sheet_id ON public.gw_strategy_sheet USING btree (bss_sheet_id);


--
-- Name: i_city_id; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX i_city_id ON public.tab_hgwcustomer USING btree (city_id);


--
-- Name: i_credno; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX i_credno ON public.tab_hgwcustomer USING btree (credno);


--
-- Name: i_dev_cpe_allocatedstatus; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX i_dev_cpe_allocatedstatus ON public.tab_gw_device USING btree (cpe_allocatedstatus);


--
-- Name: i_dev_customerid; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX i_dev_customerid ON public.tab_gw_device USING btree (customer_id);


--
-- Name: i_dev_devicetype_id; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX i_dev_devicetype_id ON public.tab_gw_device USING btree (devicetype_id);


--
-- Name: i_dev_ip; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX i_dev_ip ON public.gw_acs_stream USING btree (device_ip);


--
-- Name: i_device_model_id_device; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX i_device_model_id_device ON public.tab_gw_device USING btree (device_model_id);


--
-- Name: i_devid_gw_lan_eth_namechange; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX i_devid_gw_lan_eth_namechange ON public.gw_lan_eth_namechange USING btree (device_id);


--
-- Name: i_devid_gw_lan_wlan; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX i_devid_gw_lan_wlan ON public.gw_lan_wlan_namechange USING btree (device_id);


--
-- Name: i_diagnosis_wan_conn; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX i_diagnosis_wan_conn ON public.tab_diagnosis_wan_conn USING btree (device_id);


--
-- Name: i_downlink_tab_netacc_spead; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX i_downlink_tab_netacc_spead ON public.tab_netacc_spead USING btree (downlink);


--
-- Name: i_egwcust_serv_info_user_id; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX i_egwcust_serv_info_user_id ON public.egwcust_serv_info USING btree (user_id);


--
-- Name: i_egwcust_serv_info_username; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX i_egwcust_serv_info_username ON public.egwcust_serv_info USING btree (username);


--
-- Name: i_gather_node; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX i_gather_node ON public.tab_batchgather_node USING btree (device_id);


--
-- Name: i_gw_serv_strategy_dev_id; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX i_gw_serv_strategy_dev_id ON public.gw_serv_strategy USING btree (device_id);


--
-- Name: i_gw_serv_strategy_dev_id_serv; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX i_gw_serv_strategy_dev_id_serv ON public.gw_serv_strategy_serv USING btree (device_id);


--
-- Name: i_gw_serv_strategy_soft_dev_id; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX i_gw_serv_strategy_soft_dev_id ON public.gw_serv_strategy_soft USING btree (device_id);


--
-- Name: i_gw_strategy_serv_time; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX i_gw_strategy_serv_time ON public.gw_serv_strategy_serv_log USING btree ("time");


--
-- Name: i_gw_strategy_time_soft; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX i_gw_strategy_time_soft ON public.gw_serv_strategy_soft USING btree ("time");


--
-- Name: i_id_tab_gw_device_stbmac; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX i_id_tab_gw_device_stbmac ON public.tab_gw_device_stbmac USING btree (id);


--
-- Name: i_init_sub_sn; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX i_init_sub_sn ON public.tab_gw_device_init USING btree (dev_sub_sn);


--
-- Name: i_last_time; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX i_last_time ON public.gw_devicestatus USING btree (last_time);


--
-- Name: i_name; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE UNIQUE INDEX i_name ON public.tab_item USING btree (item_name);


--
-- Name: i_oper_time; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX i_oper_time ON public.tab_oper_log USING btree (operation_time);


--
-- Name: i_oui_sn; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX i_oui_sn ON public.tab_hgwcustomer USING btree (oui, device_serialnumber, user_state);


--
-- Name: i_oui_sn_egw; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX i_oui_sn_egw ON public.tab_egwcustomer USING btree (oui, device_serialnumber);


--
-- Name: i_prod_spec_id; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX i_prod_spec_id ON public.tab_bss_sheet USING btree (product_spec_id);


--
-- Name: i_res_area_res_id; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX i_res_area_res_id ON public.tab_gw_res_area USING btree (res_id);


--
-- Name: i_sheet_id; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX i_sheet_id ON public.tab_sheet_para USING btree (sheet_id);


--
-- Name: i_sn; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX i_sn ON public.tab_gw_device USING btree (device_serialnumber);


--
-- Name: i_speed_dev_sn; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX i_speed_dev_sn ON public.tab_speed_dev_rate USING btree (device_serialnumber);


--
-- Name: i_speed_pppoe; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX i_speed_pppoe ON public.tab_speed_dev_rate USING btree (pppoe_name);


--
-- Name: i_speed_result_dev_id; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX i_speed_result_dev_id ON public.tab_intf_speed_result USING btree (device_id);


--
-- Name: i_speed_result_dev_sn; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX i_speed_result_dev_sn ON public.tab_intf_speed_result USING btree (device_serialnumber);


--
-- Name: i_speed_result_username; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX i_speed_result_username ON public.tab_intf_speed_result USING btree (username);


--
-- Name: i_speedtask_devid; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX i_speedtask_devid ON public.tab_batchhttp_task_dev USING btree (device_id);


--
-- Name: i_speedtask_id; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX i_speedtask_id ON public.tab_batchhttp_task USING btree (task_id);


--
-- Name: i_speedtask_sn; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX i_speedtask_sn ON public.tab_batchhttp_task_dev USING btree (device_serialnumber);


--
-- Name: i_speedtask_status; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX i_speedtask_status ON public.tab_batchhttp_task_dev USING btree (status);


--
-- Name: i_speedtask_taskid; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX i_speedtask_taskid ON public.tab_batchhttp_task_dev USING btree (task_id);


--
-- Name: i_stb_dev_cpe_allocatedstatus; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX i_stb_dev_cpe_allocatedstatus ON public.stb_tab_gw_device USING btree (cpe_allocatedstatus);


--
-- Name: i_stb_dev_customerid; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX i_stb_dev_customerid ON public.stb_tab_gw_device USING btree (customer_id);


--
-- Name: i_stb_dev_devicetype_id; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX i_stb_dev_devicetype_id ON public.stb_tab_gw_device USING btree (devicetype_id);


--
-- Name: i_stb_last_time; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX i_stb_last_time ON public.stb_gw_devicestatus USING btree (last_time);


--
-- Name: i_stb_sn; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX i_stb_sn ON public.stb_tab_gw_device USING btree (device_serialnumber);


--
-- Name: i_stb_tab_gw_device_cpe_mac; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX i_stb_tab_gw_device_cpe_mac ON public.stb_tab_gw_device USING btree (cpe_mac);


--
-- Name: i_stb_tab_gw_device_dev_sub_sn; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX i_stb_tab_gw_device_dev_sub_sn ON public.stb_tab_gw_device USING btree (dev_sub_sn);


--
-- Name: i_strategy_serv_status; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX i_strategy_serv_status ON public.gw_serv_strategy_serv USING btree (status, type);


--
-- Name: i_strategy_serv_time; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX i_strategy_serv_time ON public.gw_serv_strategy_serv USING btree ("time");


--
-- Name: i_strategy_soft_status; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX i_strategy_soft_status ON public.gw_serv_strategy_soft USING btree (status, type);


--
-- Name: i_strategy_status; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX i_strategy_status ON public.gw_serv_strategy USING btree (status, type);


--
-- Name: i_tab_bss_sheet_time; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX i_tab_bss_sheet_time ON public.tab_bss_sheet USING btree (receive_date);


--
-- Name: i_tab_device_ty_version; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX i_tab_device_ty_version ON public.tab_device_ty_version USING btree (devicetype_id);


--
-- Name: i_tab_diagnosis_iad; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX i_tab_diagnosis_iad ON public.tab_diagnosis_iad USING btree (device_id);


--
-- Name: i_tab_diagnosis_poninfo; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX i_tab_diagnosis_poninfo ON public.tab_diagnosis_poninfo USING btree (device_id);


--
-- Name: i_tab_diagnosis_voipline; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX i_tab_diagnosis_voipline ON public.tab_diagnosis_voipline USING btree (device_id);


--
-- Name: i_tab_gather_interface; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX i_tab_gather_interface ON public.tab_gather_interface USING btree (device_id, interfacename);


--
-- Name: i_tab_hgw_router_app_type; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX i_tab_hgw_router_app_type ON public.tab_hgw_router USING btree (app_type);


--
-- Name: i_tab_hgw_router_router_id; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX i_tab_hgw_router_router_id ON public.tab_hgw_router USING btree (router_id);


--
-- Name: i_tab_hgw_router_user_id; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX i_tab_hgw_router_user_id ON public.tab_hgw_router USING btree (user_id);


--
-- Name: i_tab_http_speedtest; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX i_tab_http_speedtest ON public.tab_http_speedtest USING btree (device_id);


--
-- Name: i_tab_lan_speed_report_cname; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX i_tab_lan_speed_report_cname ON public.tab_lan_speed_report USING btree (city_name);


--
-- Name: i_tab_lan_speed_report_dev; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX i_tab_lan_speed_report_dev ON public.tab_lan_speed_report USING btree (device_id);


--
-- Name: i_tab_lan_speed_report_gtime; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX i_tab_lan_speed_report_gtime ON public.tab_lan_speed_report USING btree (gather_time);


--
-- Name: i_tab_lan_speed_report_rate; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX i_tab_lan_speed_report_rate ON public.tab_lan_speed_report USING btree (max_bit_rate);


--
-- Name: i_tab_lan_speed_report_user; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX i_tab_lan_speed_report_user ON public.tab_lan_speed_report USING btree (username);


--
-- Name: i_tab_lan_speed_report_utime; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX i_tab_lan_speed_report_utime ON public.tab_lan_speed_report USING btree (update_time);


--
-- Name: i_tab_modify_vlan_task_dev; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX i_tab_modify_vlan_task_dev ON public.tab_modify_vlan_task_dev USING btree (task_id, device_id);


--
-- Name: i_tab_restartdev; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX i_tab_restartdev ON public.tab_restartdev USING btree (task_id, device_id);


--
-- Name: i_tab_sheet_cmd_sheet_id; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX i_tab_sheet_cmd_sheet_id ON public.tab_sheet_cmd USING btree (sheet_id);


--
-- Name: i_tab_speed_param_city_id; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX i_tab_speed_param_city_id ON public.tab_speed_param USING btree (city_id);


--
-- Name: i_tab_stack_task_serv; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX i_tab_stack_task_serv ON public.tab_stack_task_dev USING btree (task_id, device_id);


--
-- Name: i_tab_temporary_device; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX i_tab_temporary_device ON public.tab_temporary_device USING btree (filename);


--
-- Name: i_tab_version_type; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX i_tab_version_type ON public.tab_version_type USING btree (device_version_type);


--
-- Name: i_tab_zhijia_device_sn; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX i_tab_zhijia_device_sn ON public.tab_gw_zhijia_device USING btree (device_serialnumber, oui);


--
-- Name: i_taskid_devid; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX i_taskid_devid ON public.tab_wirelesst_task_dev USING btree (task_id, device_id);


--
-- Name: i_taskid_wirelesst; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX i_taskid_wirelesst ON public.tab_wirelesst_task_dev USING btree (task_id);


--
-- Name: i_temp_id; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX i_temp_id ON public.gw_serv_strategy USING btree (temp_id);


--
-- Name: i_temp_id_serv; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX i_temp_id_serv ON public.gw_serv_strategy_serv USING btree (temp_id);


--
-- Name: i_temp_id_soft; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX i_temp_id_soft ON public.gw_serv_strategy_soft USING btree (temp_id);


--
-- Name: i_tzrdevicesn; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX i_tzrdevicesn ON public.tab_zeroconfig_report USING btree (device_sn);


--
-- Name: i_user_id; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX i_user_id ON public.gw_cust_user_dev_type USING btree (user_id);


--
-- Name: i_userinfo; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX i_userinfo ON public.tab_zeroconfig_report USING btree (user_info);


--
-- Name: i_username_egw; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE UNIQUE INDEX i_username_egw ON public.tab_egwcustomer USING btree (username);


--
-- Name: i_vendor_id; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX i_vendor_id ON public.tab_gw_device USING btree (vendor_id);


--
-- Name: i_vendor_id_devmodel; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX i_vendor_id_devmodel ON public.gw_device_model USING btree (vendor_id);


--
-- Name: idx_calc_batch_task; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX idx_calc_batch_task ON public.gw_serv_strategy_soft_log USING btree (status, result_id, task_id);


--
-- Name: idx_device_id; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX idx_device_id ON public.tab_http_telnet_switch_record USING btree (device_id);


--
-- Name: idx_device_id1; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX idx_device_id1 ON public.tab_hgwcustomer USING btree (device_id);


--
-- Name: idx_device_id_performance; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX idx_device_id_performance ON public.tab_oss_performance USING btree (device_id);


--
-- Name: idx_device_id_tt; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX idx_device_id_tt ON public.tab_tt_alarm_fail USING btree (device_id);


--
-- Name: idx_device_sn; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX idx_device_sn ON public.tab_http_telnet_switch_record USING btree (device_sn);


--
-- Name: idx_device_sn_origin; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX idx_device_sn_origin ON public.tab_register_serv_origin USING btree (device_sn);


--
-- Name: idx_device_sn_performance; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX idx_device_sn_performance ON public.tab_oss_performance USING btree (devsn);


--
-- Name: idx_device_switch_type; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX idx_device_switch_type ON public.tab_http_telnet_switch_record USING btree (device_id, switch_type);


--
-- Name: idx_device_type; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX idx_device_type ON public.tab_quality_issue_analysis USING btree (device_type);


--
-- Name: idx_device_update_time; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX idx_device_update_time ON public.tab_quality_issue_analysis USING btree (device_id, last_update_time DESC);


--
-- Name: idx_id_status; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX idx_id_status ON public.tab_batch_task_dev USING btree (task_id, status);


--
-- Name: idx_import_data_id; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX idx_import_data_id ON public.tab_import_data_temp USING btree (import_data_id);


--
-- Name: idx_indicator_identifier; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX idx_indicator_identifier ON public.tab_quality_issue_kpi_rule USING btree (indicator_identifier);


--
-- Name: idx_is_fixed; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX idx_is_fixed ON public.tab_quality_issue_analysis USING btree (is_fixed);


--
-- Name: idx_issue_fixed; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX idx_issue_fixed ON public.tab_quality_issue_analysis USING btree (quality_issue_label, is_fixed);


--
-- Name: idx_last_update_time; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX idx_last_update_time ON public.tab_quality_issue_analysis USING btree (last_update_time DESC);


--
-- Name: idx_loid; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX idx_loid ON public.stb_tab_customer USING btree (loid);


--
-- Name: idx_node_identifier; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX idx_node_identifier ON public.tab_quality_issue_kpi_rule USING btree (node_identifier);


--
-- Name: idx_online_status; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX idx_online_status ON public.gw_devicestatus USING btree (online_status);


--
-- Name: idx_quality_issue_code; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX idx_quality_issue_code ON public.tab_quality_issue_kpi_rule USING btree (quality_issue_code);


--
-- Name: idx_quality_issue_label; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX idx_quality_issue_label ON public.tab_quality_issue_analysis USING btree (quality_issue_label);


--
-- Name: idx_record_time; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX idx_record_time ON public.tab_http_telnet_switch_record USING btree (open_time);


--
-- Name: idx_sc_code; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE UNIQUE INDEX idx_sc_code ON public.sys_category USING btree (code);


--
-- Name: idx_sd_depart_order; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX idx_sd_depart_order ON public.sys_depart USING btree (depart_order);


--
-- Name: idx_sd_parent_id; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX idx_sd_parent_id ON public.sys_depart USING btree (parent_id);


--
-- Name: idx_sdi_dict_val; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX idx_sdi_dict_val ON public.sys_dict_item USING btree (item_value, dict_id);


--
-- Name: idx_sdi_role_dict_id; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX idx_sdi_role_dict_id ON public.sys_dict_item USING btree (dict_id);


--
-- Name: idx_sdi_role_sort_order; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX idx_sdi_role_sort_order ON public.sys_dict_item USING btree (sort_order);


--
-- Name: idx_sdi_status; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX idx_sdi_status ON public.sys_dict_item USING btree (status);


--
-- Name: idx_sdrp_per_id; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX idx_sdrp_per_id ON public.sys_depart_role_permission USING btree (permission_id);


--
-- Name: idx_sdrp_role_id; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX idx_sdrp_role_id ON public.sys_depart_role_permission USING btree (role_id);


--
-- Name: idx_sdrp_role_per_id; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX idx_sdrp_role_per_id ON public.sys_depart_role_permission USING btree (role_id, permission_id);


--
-- Name: idx_serv_type; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX idx_serv_type ON public.hgwcust_serv_info USING btree (serv_type_id);


--
-- Name: idx_sl_create_time; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX idx_sl_create_time ON public.sys_log USING btree (create_time);


--
-- Name: idx_sl_log_type; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX idx_sl_log_type ON public.sys_log USING btree (log_type);


--
-- Name: idx_sl_operate_type; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX idx_sl_operate_type ON public.sys_log USING btree (operate_type);


--
-- Name: idx_sl_userid; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX idx_sl_userid ON public.sys_log USING btree (userid);


--
-- Name: idx_sp_del_flag; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX idx_sp_del_flag ON public.sys_permission USING btree (del_flag);


--
-- Name: idx_sp_hidden; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX idx_sp_hidden ON public.sys_permission USING btree (hidden);


--
-- Name: idx_sp_is_leaf; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX idx_sp_is_leaf ON public.sys_permission USING btree (is_leaf);


--
-- Name: idx_sp_is_route; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX idx_sp_is_route ON public.sys_permission USING btree (is_route);


--
-- Name: idx_sp_menu_type; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX idx_sp_menu_type ON public.sys_permission USING btree (menu_type);


--
-- Name: idx_sp_parent_id; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX idx_sp_parent_id ON public.sys_permission USING btree (parent_id);


--
-- Name: idx_sp_sort_no; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX idx_sp_sort_no ON public.sys_permission USING btree (sort_no);


--
-- Name: idx_sp_status; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX idx_sp_status ON public.sys_permission USING btree (status);


--
-- Name: idx_srp_permission_id; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX idx_srp_permission_id ON public.sys_role_permission USING btree (permission_id);


--
-- Name: idx_srp_role_id; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX idx_srp_role_id ON public.sys_role_permission USING btree (role_id);


--
-- Name: idx_srp_role_per_id; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX idx_srp_role_per_id ON public.sys_role_permission USING btree (role_id, permission_id);


--
-- Name: idx_starttime; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX idx_starttime ON public.tab_oss_performance USING btree (inserttime);


--
-- Name: idx_su_del_flag; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX idx_su_del_flag ON public.sys_user USING btree (del_flag);


--
-- Name: idx_su_status; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX idx_su_status ON public.sys_user USING btree (status);


--
-- Name: idx_sud_dep_id; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX idx_sud_dep_id ON public.sys_user_depart USING btree (dep_id);


--
-- Name: idx_sud_user_dep_id; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX idx_sud_user_dep_id ON public.sys_user_depart USING btree (dep_id, user_id);


--
-- Name: idx_sud_user_id; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX idx_sud_user_id ON public.sys_user_depart USING btree (user_id);


--
-- Name: idx_sur_role_id; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX idx_sur_role_id ON public.sys_user_role USING btree (role_id);


--
-- Name: idx_sur_user_id; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX idx_sur_user_id ON public.sys_user_role USING btree (user_id);


--
-- Name: idx_sur_user_role_id; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX idx_sur_user_role_id ON public.sys_user_role USING btree (role_id, user_id);


--
-- Name: idx_switch_type; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX idx_switch_type ON public.tab_http_telnet_switch_record USING btree (switch_type);


--
-- Name: idx_tab_capacity_log_p_call_id; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX idx_tab_capacity_log_p_call_id ON ONLY public.tab_capacity_log USING btree (call_id);


--
-- Name: idx_tab_capacity_log_p_call_time; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX idx_tab_capacity_log_p_call_time ON ONLY public.tab_capacity_log USING btree (call_time);


--
-- Name: idx_tab_capacity_log_p_device_rpc_time; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX idx_tab_capacity_log_p_device_rpc_time ON ONLY public.tab_capacity_log USING btree (device_type, rpc_type, call_time);


--
-- Name: idx_tab_capacity_log_p_serial_number; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX idx_tab_capacity_log_p_serial_number ON ONLY public.tab_capacity_log USING btree (serial_number);


--
-- Name: idx_tab_capacity_log_parameter_p_call_id; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX idx_tab_capacity_log_parameter_p_call_id ON ONLY public.tab_capacity_log_parameter USING btree (call_id);


--
-- Name: idx_tab_capacity_log_parameter_p_call_time; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX idx_tab_capacity_log_parameter_p_call_time ON ONLY public.tab_capacity_log_parameter USING btree (call_time);


--
-- Name: idx_tab_vendor_ieee_oui; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX idx_tab_vendor_ieee_oui ON public.tab_vendor_ieee USING btree (oui);


--
-- Name: idx_task_device_id; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX idx_task_device_id ON public.tab_batch_task_dev USING btree (device_id);


--
-- Name: idx_task_id_device_id; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE UNIQUE INDEX idx_task_id_device_id ON public.tab_register_cpe_origin USING btree (task_id, device_sn);


--
-- Name: idx_task_id_device_sn; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE UNIQUE INDEX idx_task_id_device_sn ON public.tab_register_cpe_origin_error USING btree (task_id, device_sn);


--
-- Name: idx_task_type; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX idx_task_type ON public.tab_whitelist_dev USING btree (task_type);


--
-- Name: idx_user_id; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX idx_user_id ON public.hgwcust_serv_info USING btree (user_id);


--
-- Name: idx_user_state; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX idx_user_state ON public.tab_hgwcustomer USING btree (user_state);


--
-- Name: idx_ux_inform_log_p_id; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX idx_ux_inform_log_p_id ON ONLY public.tab_ux_inform_log USING btree (id);


--
-- Name: idx_ux_inform_log_p_sn; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX idx_ux_inform_log_p_sn ON ONLY public.tab_ux_inform_log USING btree (serial_number);


--
-- Name: idx_ux_inform_log_p_time; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX idx_ux_inform_log_p_time ON ONLY public.tab_ux_inform_log USING btree (create_time);


--
-- Name: idx_ux_inform_log_p_time_success; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX idx_ux_inform_log_p_time_success ON ONLY public.tab_ux_inform_log USING btree (create_time, success);


--
-- Name: idx_ux_inform_log_sn; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX idx_ux_inform_log_sn ON public.tab_ux_inform_log_bak_20260324121914 USING btree (serial_number);


--
-- Name: idx_ux_inform_log_time; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX idx_ux_inform_log_time ON public.tab_ux_inform_log_bak_20260324121914 USING btree (create_time);


--
-- Name: idx_vendor; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX idx_vendor ON public.tab_quality_issue_analysis USING btree (vendor);


--
-- Name: index_ip_uni; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE UNIQUE INDEX index_ip_uni ON public.gw_subnets USING btree (subnet, inetmask, subnetgrp);


--
-- Name: index_iscompleted; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX index_iscompleted ON public.tab_dev_recovery_record USING btree (is_completed);


--
-- Name: index_loid_deviceid; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX index_loid_deviceid ON public.tab_dev_recovery_record USING btree (loid, device_id);


--
-- Name: index_oui; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX index_oui ON public.stb_tab_gw_device_init_oui USING btree (oui);


--
-- Name: index_oui1; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX index_oui1 ON public.tab_gw_device_init_oui USING btree (oui);


--
-- Name: index_speedcheck_devsn; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE UNIQUE INDEX index_speedcheck_devsn ON public.tab_batchspeedcheck_temp USING btree (device_serialnumber);


--
-- Name: index_tab_gw_device_cpe_mac; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX index_tab_gw_device_cpe_mac ON public.tab_gw_device USING btree (cpe_mac);


--
-- Name: index_tab_summary_data_ext; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX index_tab_summary_data_ext ON public.tab_summary_data USING btree (ext3);


--
-- Name: iptv_username; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE UNIQUE INDEX iptv_username ON public.tab_iptv_user USING btree (username);


--
-- Name: ix_acs_stream_content_dev_id; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX ix_acs_stream_content_dev_id ON public.gw_acs_stream_content USING btree (device_id);


--
-- Name: ix_acs_stream_content_strm_id; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX ix_acs_stream_content_strm_id ON public.gw_acs_stream_content USING btree (stream_id);


--
-- Name: ix_acs_stream_dev_id; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX ix_acs_stream_dev_id ON public.gw_acs_stream USING btree (device_id);


--
-- Name: ix_bind_log_dev_id; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX ix_bind_log_dev_id ON public.bind_log USING btree (device_id);


--
-- Name: ix_bind_log_username; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX ix_bind_log_username ON public.bind_log USING btree (username);


--
-- Name: ix_bridge_route_oper_loid; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX ix_bridge_route_oper_loid ON public.bridge_route_oper_log USING btree (loid);


--
-- Name: ix_bridge_route_oper_time; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX ix_bridge_route_oper_time ON public.bridge_route_oper_log USING btree (add_time);


--
-- Name: ix_bridge_route_oper_username; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX ix_bridge_route_oper_username ON public.bridge_route_oper_log USING btree (username);


--
-- Name: ix_city_id_tab_gw_device; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX ix_city_id_tab_gw_device ON public.tab_gw_device USING btree (city_id);


--
-- Name: ix_devicetype_id_tab_gw_device; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX ix_devicetype_id_tab_gw_device ON public.tab_gw_device USING btree (devicetype_id);


--
-- Name: ix_gw_serv_strategy_sheet_id; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX ix_gw_serv_strategy_sheet_id ON public.gw_serv_strategy USING btree (sheet_id);


--
-- Name: ix_gw_wan_conn_namechange_devi; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX ix_gw_wan_conn_namechange_devi ON public.gw_wan_conn_namechange USING btree (device_id);


--
-- Name: ix_gw_wan_namechange_devid; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX ix_gw_wan_namechange_devid ON public.gw_wan_namechange USING btree (device_id);


--
-- Name: ix_gw_wan_sess_namechange_devi; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX ix_gw_wan_sess_namechange_devi ON public.gw_wan_conn_session_namechange USING btree (device_id);


--
-- Name: ix_stb_device_city_id; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX ix_stb_device_city_id ON public.stb_tab_gw_device USING btree (city_id);


--
-- Name: ix_stb_device_customer_id; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX ix_stb_device_customer_id ON public.stb_tab_gw_device USING btree (customer_id);


--
-- Name: ix_stb_device_dev_sub_sn; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX ix_stb_device_dev_sub_sn ON public.stb_tab_gw_device USING btree (dev_sub_sn);


--
-- Name: ix_stb_device_ip; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX ix_stb_device_ip ON public.stb_tab_gw_device USING btree (loopback_ip);


--
-- Name: ix_stb_serv_strategy_batch_dev_id; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX ix_stb_serv_strategy_batch_dev_id ON public.stb_gw_serv_strategy_batch USING btree (device_id);


--
-- Name: ix_stb_serv_strategy_batch_log_dev_id; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX ix_stb_serv_strategy_batch_log_dev_id ON public.stb_gw_serv_strategy_batch_log USING btree (device_id);


--
-- Name: ix_stb_serv_strategy_batch_log_end_time; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX ix_stb_serv_strategy_batch_log_end_time ON public.stb_gw_serv_strategy_batch_log USING btree (end_time);


--
-- Name: ix_stb_serv_strategy_batch_log_status; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX ix_stb_serv_strategy_batch_log_status ON public.stb_gw_serv_strategy_batch_log USING btree (status, type);


--
-- Name: ix_stb_serv_strategy_batch_sheet_id; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX ix_stb_serv_strategy_batch_sheet_id ON public.stb_gw_serv_strategy_batch USING btree (sheet_id);


--
-- Name: ix_stb_serv_strategy_batch_status; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX ix_stb_serv_strategy_batch_status ON public.stb_gw_serv_strategy_batch USING btree (status, type);


--
-- Name: ix_stb_serv_strategy_batch_temp_id; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX ix_stb_serv_strategy_batch_temp_id ON public.stb_gw_serv_strategy_batch USING btree (temp_id);


--
-- Name: ix_stb_serv_strategy_batch_time; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX ix_stb_serv_strategy_batch_time ON public.stb_gw_serv_strategy_batch USING btree ("time");


--
-- Name: ix_stb_serv_strategy_devid; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX ix_stb_serv_strategy_devid ON public.stb_gw_serv_strategy USING btree (device_id);


--
-- Name: ix_stb_serv_strategy_dst; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX ix_stb_serv_strategy_dst ON public.stb_gw_serv_strategy USING btree (status, type, device_id);


--
-- Name: ix_stb_serv_strategy_log_devid; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX ix_stb_serv_strategy_log_devid ON public.stb_gw_serv_strategy_log USING btree (device_id);


--
-- Name: ix_stb_serv_strategy_log_status; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX ix_stb_serv_strategy_log_status ON public.stb_gw_serv_strategy_log USING btree (status, type);


--
-- Name: ix_stb_serv_strategy_sheet_id; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX ix_stb_serv_strategy_sheet_id ON public.stb_gw_serv_strategy USING btree (sheet_id);


--
-- Name: ix_stb_serv_strategy_status; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX ix_stb_serv_strategy_status ON public.stb_gw_serv_strategy USING btree (status, type);


--
-- Name: ix_stb_serv_strategy_temp_id; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX ix_stb_serv_strategy_temp_id ON public.stb_gw_serv_strategy USING btree (temp_id);


--
-- Name: ix_strategy_log_status_serv; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX ix_strategy_log_status_serv ON public.gw_serv_strategy_serv_log USING btree (status, type);


--
-- Name: ix_strategy_sheet_id_serv; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX ix_strategy_sheet_id_serv ON public.gw_serv_strategy_serv USING btree (sheet_id);


--
-- Name: ix_strategy_soft_log_end_time; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX ix_strategy_soft_log_end_time ON public.gw_serv_strategy_soft_log USING btree (end_time);


--
-- Name: ix_strategy_soft_log_status; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX ix_strategy_soft_log_status ON public.gw_serv_strategy_soft_log USING btree (status, type);


--
-- Name: ix_strategy_soft_sheet_id; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX ix_strategy_soft_sheet_id ON public.gw_serv_strategy_soft USING btree (sheet_id);


--
-- Name: ix_subbind_bindid; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX ix_subbind_bindid ON public.tab_sub_bind_log USING btree (bind_id);


--
-- Name: ix_subbind_log_dev_id; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX ix_subbind_log_dev_id ON public.tab_sub_bind_log USING btree (device_id);


--
-- Name: ix_subbind_log_username; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX ix_subbind_log_username ON public.tab_sub_bind_log USING btree (username);


--
-- Name: ix_tab_gw_device_dev_sub_sn; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX ix_tab_gw_device_dev_sub_sn ON public.tab_gw_device USING btree (dev_sub_sn);


--
-- Name: ix_tab_zeroconfig_res_minute; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX ix_tab_zeroconfig_res_minute ON public.tab_zeroconfig_res_minute USING btree (add_time);


--
-- Name: log_dev_id_serv; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX log_dev_id_serv ON public.gw_serv_strategy_serv_log USING btree (device_id);


--
-- Name: log_dev_id_soft; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX log_dev_id_soft ON public.gw_serv_strategy_soft_log USING btree (device_id);


--
-- Name: oui; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX oui ON public.tab_gw_device USING btree (oui, device_serialnumber);


--
-- Name: tab_batchspeed_result_devsn; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_batchspeed_result_devsn ON public.tab_batchspeed_result_temp USING btree (devsn);


--
-- Name: tab_capacity_log_default_call_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_default_call_id_idx ON public.tab_capacity_log_default USING btree (call_id);


--
-- Name: tab_capacity_log_default_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_default_call_time_idx ON public.tab_capacity_log_default USING btree (call_time);


--
-- Name: tab_capacity_log_default_device_type_rpc_type_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_default_device_type_rpc_type_call_time_idx ON public.tab_capacity_log_default USING btree (device_type, rpc_type, call_time);


--
-- Name: tab_capacity_log_default_serial_number_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_default_serial_number_idx ON public.tab_capacity_log_default USING btree (serial_number);


--
-- Name: tab_capacity_log_p20260323_call_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260323_call_id_idx ON public.tab_capacity_log_p20260323 USING btree (call_id);


--
-- Name: tab_capacity_log_p20260323_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260323_call_time_idx ON public.tab_capacity_log_p20260323 USING btree (call_time);


--
-- Name: tab_capacity_log_p20260323_device_type_rpc_type_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260323_device_type_rpc_type_call_time_idx ON public.tab_capacity_log_p20260323 USING btree (device_type, rpc_type, call_time);


--
-- Name: tab_capacity_log_p20260323_serial_number_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260323_serial_number_idx ON public.tab_capacity_log_p20260323 USING btree (serial_number);


--
-- Name: tab_capacity_log_p20260324_call_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260324_call_id_idx ON public.tab_capacity_log_p20260324 USING btree (call_id);


--
-- Name: tab_capacity_log_p20260324_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260324_call_time_idx ON public.tab_capacity_log_p20260324 USING btree (call_time);


--
-- Name: tab_capacity_log_p20260324_device_type_rpc_type_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260324_device_type_rpc_type_call_time_idx ON public.tab_capacity_log_p20260324 USING btree (device_type, rpc_type, call_time);


--
-- Name: tab_capacity_log_p20260324_serial_number_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260324_serial_number_idx ON public.tab_capacity_log_p20260324 USING btree (serial_number);


--
-- Name: tab_capacity_log_p20260325_call_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260325_call_id_idx ON public.tab_capacity_log_p20260325 USING btree (call_id);


--
-- Name: tab_capacity_log_p20260325_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260325_call_time_idx ON public.tab_capacity_log_p20260325 USING btree (call_time);


--
-- Name: tab_capacity_log_p20260325_device_type_rpc_type_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260325_device_type_rpc_type_call_time_idx ON public.tab_capacity_log_p20260325 USING btree (device_type, rpc_type, call_time);


--
-- Name: tab_capacity_log_p20260325_serial_number_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260325_serial_number_idx ON public.tab_capacity_log_p20260325 USING btree (serial_number);


--
-- Name: tab_capacity_log_p20260326_call_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260326_call_id_idx ON public.tab_capacity_log_p20260326 USING btree (call_id);


--
-- Name: tab_capacity_log_p20260326_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260326_call_time_idx ON public.tab_capacity_log_p20260326 USING btree (call_time);


--
-- Name: tab_capacity_log_p20260326_device_type_rpc_type_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260326_device_type_rpc_type_call_time_idx ON public.tab_capacity_log_p20260326 USING btree (device_type, rpc_type, call_time);


--
-- Name: tab_capacity_log_p20260326_serial_number_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260326_serial_number_idx ON public.tab_capacity_log_p20260326 USING btree (serial_number);


--
-- Name: tab_capacity_log_p20260327_call_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260327_call_id_idx ON public.tab_capacity_log_p20260327 USING btree (call_id);


--
-- Name: tab_capacity_log_p20260327_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260327_call_time_idx ON public.tab_capacity_log_p20260327 USING btree (call_time);


--
-- Name: tab_capacity_log_p20260327_device_type_rpc_type_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260327_device_type_rpc_type_call_time_idx ON public.tab_capacity_log_p20260327 USING btree (device_type, rpc_type, call_time);


--
-- Name: tab_capacity_log_p20260327_serial_number_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260327_serial_number_idx ON public.tab_capacity_log_p20260327 USING btree (serial_number);


--
-- Name: tab_capacity_log_p20260328_call_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260328_call_id_idx ON public.tab_capacity_log_p20260328 USING btree (call_id);


--
-- Name: tab_capacity_log_p20260328_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260328_call_time_idx ON public.tab_capacity_log_p20260328 USING btree (call_time);


--
-- Name: tab_capacity_log_p20260328_device_type_rpc_type_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260328_device_type_rpc_type_call_time_idx ON public.tab_capacity_log_p20260328 USING btree (device_type, rpc_type, call_time);


--
-- Name: tab_capacity_log_p20260328_serial_number_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260328_serial_number_idx ON public.tab_capacity_log_p20260328 USING btree (serial_number);


--
-- Name: tab_capacity_log_p20260329_call_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260329_call_id_idx ON public.tab_capacity_log_p20260329 USING btree (call_id);


--
-- Name: tab_capacity_log_p20260329_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260329_call_time_idx ON public.tab_capacity_log_p20260329 USING btree (call_time);


--
-- Name: tab_capacity_log_p20260329_device_type_rpc_type_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260329_device_type_rpc_type_call_time_idx ON public.tab_capacity_log_p20260329 USING btree (device_type, rpc_type, call_time);


--
-- Name: tab_capacity_log_p20260329_serial_number_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260329_serial_number_idx ON public.tab_capacity_log_p20260329 USING btree (serial_number);


--
-- Name: tab_capacity_log_p20260330_call_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260330_call_id_idx ON public.tab_capacity_log_p20260330 USING btree (call_id);


--
-- Name: tab_capacity_log_p20260330_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260330_call_time_idx ON public.tab_capacity_log_p20260330 USING btree (call_time);


--
-- Name: tab_capacity_log_p20260330_device_type_rpc_type_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260330_device_type_rpc_type_call_time_idx ON public.tab_capacity_log_p20260330 USING btree (device_type, rpc_type, call_time);


--
-- Name: tab_capacity_log_p20260330_serial_number_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260330_serial_number_idx ON public.tab_capacity_log_p20260330 USING btree (serial_number);


--
-- Name: tab_capacity_log_p20260331_call_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260331_call_id_idx ON public.tab_capacity_log_p20260331 USING btree (call_id);


--
-- Name: tab_capacity_log_p20260331_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260331_call_time_idx ON public.tab_capacity_log_p20260331 USING btree (call_time);


--
-- Name: tab_capacity_log_p20260331_device_type_rpc_type_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260331_device_type_rpc_type_call_time_idx ON public.tab_capacity_log_p20260331 USING btree (device_type, rpc_type, call_time);


--
-- Name: tab_capacity_log_p20260331_serial_number_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260331_serial_number_idx ON public.tab_capacity_log_p20260331 USING btree (serial_number);


--
-- Name: tab_capacity_log_p20260401_call_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260401_call_id_idx ON public.tab_capacity_log_p20260401 USING btree (call_id);


--
-- Name: tab_capacity_log_p20260401_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260401_call_time_idx ON public.tab_capacity_log_p20260401 USING btree (call_time);


--
-- Name: tab_capacity_log_p20260401_device_type_rpc_type_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260401_device_type_rpc_type_call_time_idx ON public.tab_capacity_log_p20260401 USING btree (device_type, rpc_type, call_time);


--
-- Name: tab_capacity_log_p20260401_serial_number_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260401_serial_number_idx ON public.tab_capacity_log_p20260401 USING btree (serial_number);


--
-- Name: tab_capacity_log_p20260402_call_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260402_call_id_idx ON public.tab_capacity_log_p20260402 USING btree (call_id);


--
-- Name: tab_capacity_log_p20260402_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260402_call_time_idx ON public.tab_capacity_log_p20260402 USING btree (call_time);


--
-- Name: tab_capacity_log_p20260402_device_type_rpc_type_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260402_device_type_rpc_type_call_time_idx ON public.tab_capacity_log_p20260402 USING btree (device_type, rpc_type, call_time);


--
-- Name: tab_capacity_log_p20260402_serial_number_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260402_serial_number_idx ON public.tab_capacity_log_p20260402 USING btree (serial_number);


--
-- Name: tab_capacity_log_p20260403_call_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260403_call_id_idx ON public.tab_capacity_log_p20260403 USING btree (call_id);


--
-- Name: tab_capacity_log_p20260403_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260403_call_time_idx ON public.tab_capacity_log_p20260403 USING btree (call_time);


--
-- Name: tab_capacity_log_p20260403_device_type_rpc_type_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260403_device_type_rpc_type_call_time_idx ON public.tab_capacity_log_p20260403 USING btree (device_type, rpc_type, call_time);


--
-- Name: tab_capacity_log_p20260403_serial_number_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260403_serial_number_idx ON public.tab_capacity_log_p20260403 USING btree (serial_number);


--
-- Name: tab_capacity_log_p20260404_call_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260404_call_id_idx ON public.tab_capacity_log_p20260404 USING btree (call_id);


--
-- Name: tab_capacity_log_p20260404_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260404_call_time_idx ON public.tab_capacity_log_p20260404 USING btree (call_time);


--
-- Name: tab_capacity_log_p20260404_device_type_rpc_type_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260404_device_type_rpc_type_call_time_idx ON public.tab_capacity_log_p20260404 USING btree (device_type, rpc_type, call_time);


--
-- Name: tab_capacity_log_p20260404_serial_number_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260404_serial_number_idx ON public.tab_capacity_log_p20260404 USING btree (serial_number);


--
-- Name: tab_capacity_log_p20260405_call_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260405_call_id_idx ON public.tab_capacity_log_p20260405 USING btree (call_id);


--
-- Name: tab_capacity_log_p20260405_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260405_call_time_idx ON public.tab_capacity_log_p20260405 USING btree (call_time);


--
-- Name: tab_capacity_log_p20260405_device_type_rpc_type_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260405_device_type_rpc_type_call_time_idx ON public.tab_capacity_log_p20260405 USING btree (device_type, rpc_type, call_time);


--
-- Name: tab_capacity_log_p20260405_serial_number_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260405_serial_number_idx ON public.tab_capacity_log_p20260405 USING btree (serial_number);


--
-- Name: tab_capacity_log_p20260406_call_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260406_call_id_idx ON public.tab_capacity_log_p20260406 USING btree (call_id);


--
-- Name: tab_capacity_log_p20260406_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260406_call_time_idx ON public.tab_capacity_log_p20260406 USING btree (call_time);


--
-- Name: tab_capacity_log_p20260406_device_type_rpc_type_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260406_device_type_rpc_type_call_time_idx ON public.tab_capacity_log_p20260406 USING btree (device_type, rpc_type, call_time);


--
-- Name: tab_capacity_log_p20260406_serial_number_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260406_serial_number_idx ON public.tab_capacity_log_p20260406 USING btree (serial_number);


--
-- Name: tab_capacity_log_p20260407_call_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260407_call_id_idx ON public.tab_capacity_log_p20260407 USING btree (call_id);


--
-- Name: tab_capacity_log_p20260407_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260407_call_time_idx ON public.tab_capacity_log_p20260407 USING btree (call_time);


--
-- Name: tab_capacity_log_p20260407_device_type_rpc_type_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260407_device_type_rpc_type_call_time_idx ON public.tab_capacity_log_p20260407 USING btree (device_type, rpc_type, call_time);


--
-- Name: tab_capacity_log_p20260407_serial_number_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260407_serial_number_idx ON public.tab_capacity_log_p20260407 USING btree (serial_number);


--
-- Name: tab_capacity_log_p20260408_call_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260408_call_id_idx ON public.tab_capacity_log_p20260408 USING btree (call_id);


--
-- Name: tab_capacity_log_p20260408_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260408_call_time_idx ON public.tab_capacity_log_p20260408 USING btree (call_time);


--
-- Name: tab_capacity_log_p20260408_device_type_rpc_type_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260408_device_type_rpc_type_call_time_idx ON public.tab_capacity_log_p20260408 USING btree (device_type, rpc_type, call_time);


--
-- Name: tab_capacity_log_p20260408_serial_number_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260408_serial_number_idx ON public.tab_capacity_log_p20260408 USING btree (serial_number);


--
-- Name: tab_capacity_log_p20260409_call_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260409_call_id_idx ON public.tab_capacity_log_p20260409 USING btree (call_id);


--
-- Name: tab_capacity_log_p20260409_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260409_call_time_idx ON public.tab_capacity_log_p20260409 USING btree (call_time);


--
-- Name: tab_capacity_log_p20260409_device_type_rpc_type_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260409_device_type_rpc_type_call_time_idx ON public.tab_capacity_log_p20260409 USING btree (device_type, rpc_type, call_time);


--
-- Name: tab_capacity_log_p20260409_serial_number_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260409_serial_number_idx ON public.tab_capacity_log_p20260409 USING btree (serial_number);


--
-- Name: tab_capacity_log_p20260410_call_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260410_call_id_idx ON public.tab_capacity_log_p20260410 USING btree (call_id);


--
-- Name: tab_capacity_log_p20260410_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260410_call_time_idx ON public.tab_capacity_log_p20260410 USING btree (call_time);


--
-- Name: tab_capacity_log_p20260410_device_type_rpc_type_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260410_device_type_rpc_type_call_time_idx ON public.tab_capacity_log_p20260410 USING btree (device_type, rpc_type, call_time);


--
-- Name: tab_capacity_log_p20260410_serial_number_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260410_serial_number_idx ON public.tab_capacity_log_p20260410 USING btree (serial_number);


--
-- Name: tab_capacity_log_p20260411_call_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260411_call_id_idx ON public.tab_capacity_log_p20260411 USING btree (call_id);


--
-- Name: tab_capacity_log_p20260411_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260411_call_time_idx ON public.tab_capacity_log_p20260411 USING btree (call_time);


--
-- Name: tab_capacity_log_p20260411_device_type_rpc_type_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260411_device_type_rpc_type_call_time_idx ON public.tab_capacity_log_p20260411 USING btree (device_type, rpc_type, call_time);


--
-- Name: tab_capacity_log_p20260411_serial_number_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260411_serial_number_idx ON public.tab_capacity_log_p20260411 USING btree (serial_number);


--
-- Name: tab_capacity_log_p20260412_call_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260412_call_id_idx ON public.tab_capacity_log_p20260412 USING btree (call_id);


--
-- Name: tab_capacity_log_p20260412_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260412_call_time_idx ON public.tab_capacity_log_p20260412 USING btree (call_time);


--
-- Name: tab_capacity_log_p20260412_device_type_rpc_type_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260412_device_type_rpc_type_call_time_idx ON public.tab_capacity_log_p20260412 USING btree (device_type, rpc_type, call_time);


--
-- Name: tab_capacity_log_p20260412_serial_number_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260412_serial_number_idx ON public.tab_capacity_log_p20260412 USING btree (serial_number);


--
-- Name: tab_capacity_log_p20260413_call_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260413_call_id_idx ON public.tab_capacity_log_p20260413 USING btree (call_id);


--
-- Name: tab_capacity_log_p20260413_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260413_call_time_idx ON public.tab_capacity_log_p20260413 USING btree (call_time);


--
-- Name: tab_capacity_log_p20260413_device_type_rpc_type_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260413_device_type_rpc_type_call_time_idx ON public.tab_capacity_log_p20260413 USING btree (device_type, rpc_type, call_time);


--
-- Name: tab_capacity_log_p20260413_serial_number_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260413_serial_number_idx ON public.tab_capacity_log_p20260413 USING btree (serial_number);


--
-- Name: tab_capacity_log_p20260414_call_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260414_call_id_idx ON public.tab_capacity_log_p20260414 USING btree (call_id);


--
-- Name: tab_capacity_log_p20260414_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260414_call_time_idx ON public.tab_capacity_log_p20260414 USING btree (call_time);


--
-- Name: tab_capacity_log_p20260414_device_type_rpc_type_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260414_device_type_rpc_type_call_time_idx ON public.tab_capacity_log_p20260414 USING btree (device_type, rpc_type, call_time);


--
-- Name: tab_capacity_log_p20260414_serial_number_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260414_serial_number_idx ON public.tab_capacity_log_p20260414 USING btree (serial_number);


--
-- Name: tab_capacity_log_p20260415_call_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260415_call_id_idx ON public.tab_capacity_log_p20260415 USING btree (call_id);


--
-- Name: tab_capacity_log_p20260415_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260415_call_time_idx ON public.tab_capacity_log_p20260415 USING btree (call_time);


--
-- Name: tab_capacity_log_p20260415_device_type_rpc_type_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260415_device_type_rpc_type_call_time_idx ON public.tab_capacity_log_p20260415 USING btree (device_type, rpc_type, call_time);


--
-- Name: tab_capacity_log_p20260415_serial_number_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260415_serial_number_idx ON public.tab_capacity_log_p20260415 USING btree (serial_number);


--
-- Name: tab_capacity_log_p20260416_call_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260416_call_id_idx ON public.tab_capacity_log_p20260416 USING btree (call_id);


--
-- Name: tab_capacity_log_p20260416_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260416_call_time_idx ON public.tab_capacity_log_p20260416 USING btree (call_time);


--
-- Name: tab_capacity_log_p20260416_device_type_rpc_type_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260416_device_type_rpc_type_call_time_idx ON public.tab_capacity_log_p20260416 USING btree (device_type, rpc_type, call_time);


--
-- Name: tab_capacity_log_p20260416_serial_number_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260416_serial_number_idx ON public.tab_capacity_log_p20260416 USING btree (serial_number);


--
-- Name: tab_capacity_log_p20260417_call_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260417_call_id_idx ON public.tab_capacity_log_p20260417 USING btree (call_id);


--
-- Name: tab_capacity_log_p20260417_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260417_call_time_idx ON public.tab_capacity_log_p20260417 USING btree (call_time);


--
-- Name: tab_capacity_log_p20260417_device_type_rpc_type_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260417_device_type_rpc_type_call_time_idx ON public.tab_capacity_log_p20260417 USING btree (device_type, rpc_type, call_time);


--
-- Name: tab_capacity_log_p20260417_serial_number_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260417_serial_number_idx ON public.tab_capacity_log_p20260417 USING btree (serial_number);


--
-- Name: tab_capacity_log_p20260418_call_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260418_call_id_idx ON public.tab_capacity_log_p20260418 USING btree (call_id);


--
-- Name: tab_capacity_log_p20260418_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260418_call_time_idx ON public.tab_capacity_log_p20260418 USING btree (call_time);


--
-- Name: tab_capacity_log_p20260418_device_type_rpc_type_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260418_device_type_rpc_type_call_time_idx ON public.tab_capacity_log_p20260418 USING btree (device_type, rpc_type, call_time);


--
-- Name: tab_capacity_log_p20260418_serial_number_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260418_serial_number_idx ON public.tab_capacity_log_p20260418 USING btree (serial_number);


--
-- Name: tab_capacity_log_p20260419_call_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260419_call_id_idx ON public.tab_capacity_log_p20260419 USING btree (call_id);


--
-- Name: tab_capacity_log_p20260419_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260419_call_time_idx ON public.tab_capacity_log_p20260419 USING btree (call_time);


--
-- Name: tab_capacity_log_p20260419_device_type_rpc_type_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260419_device_type_rpc_type_call_time_idx ON public.tab_capacity_log_p20260419 USING btree (device_type, rpc_type, call_time);


--
-- Name: tab_capacity_log_p20260419_serial_number_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260419_serial_number_idx ON public.tab_capacity_log_p20260419 USING btree (serial_number);


--
-- Name: tab_capacity_log_p20260420_call_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260420_call_id_idx ON public.tab_capacity_log_p20260420 USING btree (call_id);


--
-- Name: tab_capacity_log_p20260420_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260420_call_time_idx ON public.tab_capacity_log_p20260420 USING btree (call_time);


--
-- Name: tab_capacity_log_p20260420_device_type_rpc_type_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260420_device_type_rpc_type_call_time_idx ON public.tab_capacity_log_p20260420 USING btree (device_type, rpc_type, call_time);


--
-- Name: tab_capacity_log_p20260420_serial_number_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260420_serial_number_idx ON public.tab_capacity_log_p20260420 USING btree (serial_number);


--
-- Name: tab_capacity_log_p20260421_call_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260421_call_id_idx ON public.tab_capacity_log_p20260421 USING btree (call_id);


--
-- Name: tab_capacity_log_p20260421_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260421_call_time_idx ON public.tab_capacity_log_p20260421 USING btree (call_time);


--
-- Name: tab_capacity_log_p20260421_device_type_rpc_type_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260421_device_type_rpc_type_call_time_idx ON public.tab_capacity_log_p20260421 USING btree (device_type, rpc_type, call_time);


--
-- Name: tab_capacity_log_p20260421_serial_number_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260421_serial_number_idx ON public.tab_capacity_log_p20260421 USING btree (serial_number);


--
-- Name: tab_capacity_log_p20260422_call_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260422_call_id_idx ON public.tab_capacity_log_p20260422 USING btree (call_id);


--
-- Name: tab_capacity_log_p20260422_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260422_call_time_idx ON public.tab_capacity_log_p20260422 USING btree (call_time);


--
-- Name: tab_capacity_log_p20260422_device_type_rpc_type_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260422_device_type_rpc_type_call_time_idx ON public.tab_capacity_log_p20260422 USING btree (device_type, rpc_type, call_time);


--
-- Name: tab_capacity_log_p20260422_serial_number_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260422_serial_number_idx ON public.tab_capacity_log_p20260422 USING btree (serial_number);


--
-- Name: tab_capacity_log_p20260423_call_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260423_call_id_idx ON public.tab_capacity_log_p20260423 USING btree (call_id);


--
-- Name: tab_capacity_log_p20260423_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260423_call_time_idx ON public.tab_capacity_log_p20260423 USING btree (call_time);


--
-- Name: tab_capacity_log_p20260423_device_type_rpc_type_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260423_device_type_rpc_type_call_time_idx ON public.tab_capacity_log_p20260423 USING btree (device_type, rpc_type, call_time);


--
-- Name: tab_capacity_log_p20260423_serial_number_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_p20260423_serial_number_idx ON public.tab_capacity_log_p20260423 USING btree (serial_number);


--
-- Name: tab_capacity_log_parameter_default_call_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_parameter_default_call_id_idx ON public.tab_capacity_log_parameter_default USING btree (call_id);


--
-- Name: tab_capacity_log_parameter_default_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_parameter_default_call_time_idx ON public.tab_capacity_log_parameter_default USING btree (call_time);


--
-- Name: tab_capacity_log_parameter_p20260323_call_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_parameter_p20260323_call_id_idx ON public.tab_capacity_log_parameter_p20260323 USING btree (call_id);


--
-- Name: tab_capacity_log_parameter_p20260323_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_parameter_p20260323_call_time_idx ON public.tab_capacity_log_parameter_p20260323 USING btree (call_time);


--
-- Name: tab_capacity_log_parameter_p20260324_call_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_parameter_p20260324_call_id_idx ON public.tab_capacity_log_parameter_p20260324 USING btree (call_id);


--
-- Name: tab_capacity_log_parameter_p20260324_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_parameter_p20260324_call_time_idx ON public.tab_capacity_log_parameter_p20260324 USING btree (call_time);


--
-- Name: tab_capacity_log_parameter_p20260325_call_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_parameter_p20260325_call_id_idx ON public.tab_capacity_log_parameter_p20260325 USING btree (call_id);


--
-- Name: tab_capacity_log_parameter_p20260325_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_parameter_p20260325_call_time_idx ON public.tab_capacity_log_parameter_p20260325 USING btree (call_time);


--
-- Name: tab_capacity_log_parameter_p20260326_call_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_parameter_p20260326_call_id_idx ON public.tab_capacity_log_parameter_p20260326 USING btree (call_id);


--
-- Name: tab_capacity_log_parameter_p20260326_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_parameter_p20260326_call_time_idx ON public.tab_capacity_log_parameter_p20260326 USING btree (call_time);


--
-- Name: tab_capacity_log_parameter_p20260327_call_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_parameter_p20260327_call_id_idx ON public.tab_capacity_log_parameter_p20260327 USING btree (call_id);


--
-- Name: tab_capacity_log_parameter_p20260327_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_parameter_p20260327_call_time_idx ON public.tab_capacity_log_parameter_p20260327 USING btree (call_time);


--
-- Name: tab_capacity_log_parameter_p20260328_call_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_parameter_p20260328_call_id_idx ON public.tab_capacity_log_parameter_p20260328 USING btree (call_id);


--
-- Name: tab_capacity_log_parameter_p20260328_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_parameter_p20260328_call_time_idx ON public.tab_capacity_log_parameter_p20260328 USING btree (call_time);


--
-- Name: tab_capacity_log_parameter_p20260329_call_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_parameter_p20260329_call_id_idx ON public.tab_capacity_log_parameter_p20260329 USING btree (call_id);


--
-- Name: tab_capacity_log_parameter_p20260329_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_parameter_p20260329_call_time_idx ON public.tab_capacity_log_parameter_p20260329 USING btree (call_time);


--
-- Name: tab_capacity_log_parameter_p20260330_call_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_parameter_p20260330_call_id_idx ON public.tab_capacity_log_parameter_p20260330 USING btree (call_id);


--
-- Name: tab_capacity_log_parameter_p20260330_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_parameter_p20260330_call_time_idx ON public.tab_capacity_log_parameter_p20260330 USING btree (call_time);


--
-- Name: tab_capacity_log_parameter_p20260331_call_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_parameter_p20260331_call_id_idx ON public.tab_capacity_log_parameter_p20260331 USING btree (call_id);


--
-- Name: tab_capacity_log_parameter_p20260331_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_parameter_p20260331_call_time_idx ON public.tab_capacity_log_parameter_p20260331 USING btree (call_time);


--
-- Name: tab_capacity_log_parameter_p20260401_call_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_parameter_p20260401_call_id_idx ON public.tab_capacity_log_parameter_p20260401 USING btree (call_id);


--
-- Name: tab_capacity_log_parameter_p20260401_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_parameter_p20260401_call_time_idx ON public.tab_capacity_log_parameter_p20260401 USING btree (call_time);


--
-- Name: tab_capacity_log_parameter_p20260402_call_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_parameter_p20260402_call_id_idx ON public.tab_capacity_log_parameter_p20260402 USING btree (call_id);


--
-- Name: tab_capacity_log_parameter_p20260402_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_parameter_p20260402_call_time_idx ON public.tab_capacity_log_parameter_p20260402 USING btree (call_time);


--
-- Name: tab_capacity_log_parameter_p20260403_call_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_parameter_p20260403_call_id_idx ON public.tab_capacity_log_parameter_p20260403 USING btree (call_id);


--
-- Name: tab_capacity_log_parameter_p20260403_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_parameter_p20260403_call_time_idx ON public.tab_capacity_log_parameter_p20260403 USING btree (call_time);


--
-- Name: tab_capacity_log_parameter_p20260404_call_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_parameter_p20260404_call_id_idx ON public.tab_capacity_log_parameter_p20260404 USING btree (call_id);


--
-- Name: tab_capacity_log_parameter_p20260404_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_parameter_p20260404_call_time_idx ON public.tab_capacity_log_parameter_p20260404 USING btree (call_time);


--
-- Name: tab_capacity_log_parameter_p20260405_call_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_parameter_p20260405_call_id_idx ON public.tab_capacity_log_parameter_p20260405 USING btree (call_id);


--
-- Name: tab_capacity_log_parameter_p20260405_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_parameter_p20260405_call_time_idx ON public.tab_capacity_log_parameter_p20260405 USING btree (call_time);


--
-- Name: tab_capacity_log_parameter_p20260406_call_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_parameter_p20260406_call_id_idx ON public.tab_capacity_log_parameter_p20260406 USING btree (call_id);


--
-- Name: tab_capacity_log_parameter_p20260406_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_parameter_p20260406_call_time_idx ON public.tab_capacity_log_parameter_p20260406 USING btree (call_time);


--
-- Name: tab_capacity_log_parameter_p20260407_call_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_parameter_p20260407_call_id_idx ON public.tab_capacity_log_parameter_p20260407 USING btree (call_id);


--
-- Name: tab_capacity_log_parameter_p20260407_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_parameter_p20260407_call_time_idx ON public.tab_capacity_log_parameter_p20260407 USING btree (call_time);


--
-- Name: tab_capacity_log_parameter_p20260408_call_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_parameter_p20260408_call_id_idx ON public.tab_capacity_log_parameter_p20260408 USING btree (call_id);


--
-- Name: tab_capacity_log_parameter_p20260408_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_parameter_p20260408_call_time_idx ON public.tab_capacity_log_parameter_p20260408 USING btree (call_time);


--
-- Name: tab_capacity_log_parameter_p20260409_call_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_parameter_p20260409_call_id_idx ON public.tab_capacity_log_parameter_p20260409 USING btree (call_id);


--
-- Name: tab_capacity_log_parameter_p20260409_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_parameter_p20260409_call_time_idx ON public.tab_capacity_log_parameter_p20260409 USING btree (call_time);


--
-- Name: tab_capacity_log_parameter_p20260410_call_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_parameter_p20260410_call_id_idx ON public.tab_capacity_log_parameter_p20260410 USING btree (call_id);


--
-- Name: tab_capacity_log_parameter_p20260410_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_parameter_p20260410_call_time_idx ON public.tab_capacity_log_parameter_p20260410 USING btree (call_time);


--
-- Name: tab_capacity_log_parameter_p20260411_call_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_parameter_p20260411_call_id_idx ON public.tab_capacity_log_parameter_p20260411 USING btree (call_id);


--
-- Name: tab_capacity_log_parameter_p20260411_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_parameter_p20260411_call_time_idx ON public.tab_capacity_log_parameter_p20260411 USING btree (call_time);


--
-- Name: tab_capacity_log_parameter_p20260412_call_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_parameter_p20260412_call_id_idx ON public.tab_capacity_log_parameter_p20260412 USING btree (call_id);


--
-- Name: tab_capacity_log_parameter_p20260412_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_parameter_p20260412_call_time_idx ON public.tab_capacity_log_parameter_p20260412 USING btree (call_time);


--
-- Name: tab_capacity_log_parameter_p20260413_call_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_parameter_p20260413_call_id_idx ON public.tab_capacity_log_parameter_p20260413 USING btree (call_id);


--
-- Name: tab_capacity_log_parameter_p20260413_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_parameter_p20260413_call_time_idx ON public.tab_capacity_log_parameter_p20260413 USING btree (call_time);


--
-- Name: tab_capacity_log_parameter_p20260414_call_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_parameter_p20260414_call_id_idx ON public.tab_capacity_log_parameter_p20260414 USING btree (call_id);


--
-- Name: tab_capacity_log_parameter_p20260414_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_parameter_p20260414_call_time_idx ON public.tab_capacity_log_parameter_p20260414 USING btree (call_time);


--
-- Name: tab_capacity_log_parameter_p20260415_call_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_parameter_p20260415_call_id_idx ON public.tab_capacity_log_parameter_p20260415 USING btree (call_id);


--
-- Name: tab_capacity_log_parameter_p20260415_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_parameter_p20260415_call_time_idx ON public.tab_capacity_log_parameter_p20260415 USING btree (call_time);


--
-- Name: tab_capacity_log_parameter_p20260416_call_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_parameter_p20260416_call_id_idx ON public.tab_capacity_log_parameter_p20260416 USING btree (call_id);


--
-- Name: tab_capacity_log_parameter_p20260416_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_parameter_p20260416_call_time_idx ON public.tab_capacity_log_parameter_p20260416 USING btree (call_time);


--
-- Name: tab_capacity_log_parameter_p20260417_call_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_parameter_p20260417_call_id_idx ON public.tab_capacity_log_parameter_p20260417 USING btree (call_id);


--
-- Name: tab_capacity_log_parameter_p20260417_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_parameter_p20260417_call_time_idx ON public.tab_capacity_log_parameter_p20260417 USING btree (call_time);


--
-- Name: tab_capacity_log_parameter_p20260418_call_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_parameter_p20260418_call_id_idx ON public.tab_capacity_log_parameter_p20260418 USING btree (call_id);


--
-- Name: tab_capacity_log_parameter_p20260418_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_parameter_p20260418_call_time_idx ON public.tab_capacity_log_parameter_p20260418 USING btree (call_time);


--
-- Name: tab_capacity_log_parameter_p20260419_call_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_parameter_p20260419_call_id_idx ON public.tab_capacity_log_parameter_p20260419 USING btree (call_id);


--
-- Name: tab_capacity_log_parameter_p20260419_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_parameter_p20260419_call_time_idx ON public.tab_capacity_log_parameter_p20260419 USING btree (call_time);


--
-- Name: tab_capacity_log_parameter_p20260420_call_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_parameter_p20260420_call_id_idx ON public.tab_capacity_log_parameter_p20260420 USING btree (call_id);


--
-- Name: tab_capacity_log_parameter_p20260420_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_parameter_p20260420_call_time_idx ON public.tab_capacity_log_parameter_p20260420 USING btree (call_time);


--
-- Name: tab_capacity_log_parameter_p20260421_call_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_parameter_p20260421_call_id_idx ON public.tab_capacity_log_parameter_p20260421 USING btree (call_id);


--
-- Name: tab_capacity_log_parameter_p20260421_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_parameter_p20260421_call_time_idx ON public.tab_capacity_log_parameter_p20260421 USING btree (call_time);


--
-- Name: tab_capacity_log_parameter_p20260422_call_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_parameter_p20260422_call_id_idx ON public.tab_capacity_log_parameter_p20260422 USING btree (call_id);


--
-- Name: tab_capacity_log_parameter_p20260422_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_parameter_p20260422_call_time_idx ON public.tab_capacity_log_parameter_p20260422 USING btree (call_time);


--
-- Name: tab_capacity_log_parameter_p20260423_call_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_parameter_p20260423_call_id_idx ON public.tab_capacity_log_parameter_p20260423 USING btree (call_id);


--
-- Name: tab_capacity_log_parameter_p20260423_call_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_capacity_log_parameter_p20260423_call_time_idx ON public.tab_capacity_log_parameter_p20260423 USING btree (call_time);


--
-- Name: tab_quality_issue_repair_his_measures_id_index; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_quality_issue_repair_his_measures_id_index ON public.tab_quality_issue_repair_his USING btree (measures_id);


--
-- Name: tab_ux_inform_log_default_create_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_default_create_time_idx ON public.tab_ux_inform_log_default USING btree (create_time);


--
-- Name: tab_ux_inform_log_default_create_time_success_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_default_create_time_success_idx ON public.tab_ux_inform_log_default USING btree (create_time, success);


--
-- Name: tab_ux_inform_log_default_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_default_id_idx ON public.tab_ux_inform_log_default USING btree (id);


--
-- Name: tab_ux_inform_log_default_serial_number_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_default_serial_number_idx ON public.tab_ux_inform_log_default USING btree (serial_number);


--
-- Name: tab_ux_inform_log_p20260323_create_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260323_create_time_idx ON public.tab_ux_inform_log_p20260323 USING btree (create_time);


--
-- Name: tab_ux_inform_log_p20260323_create_time_success_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260323_create_time_success_idx ON public.tab_ux_inform_log_p20260323 USING btree (create_time, success);


--
-- Name: tab_ux_inform_log_p20260323_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260323_id_idx ON public.tab_ux_inform_log_p20260323 USING btree (id);


--
-- Name: tab_ux_inform_log_p20260323_serial_number_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260323_serial_number_idx ON public.tab_ux_inform_log_p20260323 USING btree (serial_number);


--
-- Name: tab_ux_inform_log_p20260324_create_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260324_create_time_idx ON public.tab_ux_inform_log_p20260324 USING btree (create_time);


--
-- Name: tab_ux_inform_log_p20260324_create_time_success_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260324_create_time_success_idx ON public.tab_ux_inform_log_p20260324 USING btree (create_time, success);


--
-- Name: tab_ux_inform_log_p20260324_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260324_id_idx ON public.tab_ux_inform_log_p20260324 USING btree (id);


--
-- Name: tab_ux_inform_log_p20260324_serial_number_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260324_serial_number_idx ON public.tab_ux_inform_log_p20260324 USING btree (serial_number);


--
-- Name: tab_ux_inform_log_p20260325_create_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260325_create_time_idx ON public.tab_ux_inform_log_p20260325 USING btree (create_time);


--
-- Name: tab_ux_inform_log_p20260325_create_time_success_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260325_create_time_success_idx ON public.tab_ux_inform_log_p20260325 USING btree (create_time, success);


--
-- Name: tab_ux_inform_log_p20260325_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260325_id_idx ON public.tab_ux_inform_log_p20260325 USING btree (id);


--
-- Name: tab_ux_inform_log_p20260325_serial_number_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260325_serial_number_idx ON public.tab_ux_inform_log_p20260325 USING btree (serial_number);


--
-- Name: tab_ux_inform_log_p20260326_create_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260326_create_time_idx ON public.tab_ux_inform_log_p20260326 USING btree (create_time);


--
-- Name: tab_ux_inform_log_p20260326_create_time_success_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260326_create_time_success_idx ON public.tab_ux_inform_log_p20260326 USING btree (create_time, success);


--
-- Name: tab_ux_inform_log_p20260326_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260326_id_idx ON public.tab_ux_inform_log_p20260326 USING btree (id);


--
-- Name: tab_ux_inform_log_p20260326_serial_number_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260326_serial_number_idx ON public.tab_ux_inform_log_p20260326 USING btree (serial_number);


--
-- Name: tab_ux_inform_log_p20260327_create_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260327_create_time_idx ON public.tab_ux_inform_log_p20260327 USING btree (create_time);


--
-- Name: tab_ux_inform_log_p20260327_create_time_success_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260327_create_time_success_idx ON public.tab_ux_inform_log_p20260327 USING btree (create_time, success);


--
-- Name: tab_ux_inform_log_p20260327_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260327_id_idx ON public.tab_ux_inform_log_p20260327 USING btree (id);


--
-- Name: tab_ux_inform_log_p20260327_serial_number_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260327_serial_number_idx ON public.tab_ux_inform_log_p20260327 USING btree (serial_number);


--
-- Name: tab_ux_inform_log_p20260328_create_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260328_create_time_idx ON public.tab_ux_inform_log_p20260328 USING btree (create_time);


--
-- Name: tab_ux_inform_log_p20260328_create_time_success_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260328_create_time_success_idx ON public.tab_ux_inform_log_p20260328 USING btree (create_time, success);


--
-- Name: tab_ux_inform_log_p20260328_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260328_id_idx ON public.tab_ux_inform_log_p20260328 USING btree (id);


--
-- Name: tab_ux_inform_log_p20260328_serial_number_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260328_serial_number_idx ON public.tab_ux_inform_log_p20260328 USING btree (serial_number);


--
-- Name: tab_ux_inform_log_p20260329_create_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260329_create_time_idx ON public.tab_ux_inform_log_p20260329 USING btree (create_time);


--
-- Name: tab_ux_inform_log_p20260329_create_time_success_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260329_create_time_success_idx ON public.tab_ux_inform_log_p20260329 USING btree (create_time, success);


--
-- Name: tab_ux_inform_log_p20260329_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260329_id_idx ON public.tab_ux_inform_log_p20260329 USING btree (id);


--
-- Name: tab_ux_inform_log_p20260329_serial_number_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260329_serial_number_idx ON public.tab_ux_inform_log_p20260329 USING btree (serial_number);


--
-- Name: tab_ux_inform_log_p20260330_create_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260330_create_time_idx ON public.tab_ux_inform_log_p20260330 USING btree (create_time);


--
-- Name: tab_ux_inform_log_p20260330_create_time_success_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260330_create_time_success_idx ON public.tab_ux_inform_log_p20260330 USING btree (create_time, success);


--
-- Name: tab_ux_inform_log_p20260330_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260330_id_idx ON public.tab_ux_inform_log_p20260330 USING btree (id);


--
-- Name: tab_ux_inform_log_p20260330_serial_number_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260330_serial_number_idx ON public.tab_ux_inform_log_p20260330 USING btree (serial_number);


--
-- Name: tab_ux_inform_log_p20260331_create_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260331_create_time_idx ON public.tab_ux_inform_log_p20260331 USING btree (create_time);


--
-- Name: tab_ux_inform_log_p20260331_create_time_success_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260331_create_time_success_idx ON public.tab_ux_inform_log_p20260331 USING btree (create_time, success);


--
-- Name: tab_ux_inform_log_p20260331_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260331_id_idx ON public.tab_ux_inform_log_p20260331 USING btree (id);


--
-- Name: tab_ux_inform_log_p20260331_serial_number_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260331_serial_number_idx ON public.tab_ux_inform_log_p20260331 USING btree (serial_number);


--
-- Name: tab_ux_inform_log_p20260401_create_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260401_create_time_idx ON public.tab_ux_inform_log_p20260401 USING btree (create_time);


--
-- Name: tab_ux_inform_log_p20260401_create_time_success_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260401_create_time_success_idx ON public.tab_ux_inform_log_p20260401 USING btree (create_time, success);


--
-- Name: tab_ux_inform_log_p20260401_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260401_id_idx ON public.tab_ux_inform_log_p20260401 USING btree (id);


--
-- Name: tab_ux_inform_log_p20260401_serial_number_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260401_serial_number_idx ON public.tab_ux_inform_log_p20260401 USING btree (serial_number);


--
-- Name: tab_ux_inform_log_p20260402_create_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260402_create_time_idx ON public.tab_ux_inform_log_p20260402 USING btree (create_time);


--
-- Name: tab_ux_inform_log_p20260402_create_time_success_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260402_create_time_success_idx ON public.tab_ux_inform_log_p20260402 USING btree (create_time, success);


--
-- Name: tab_ux_inform_log_p20260402_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260402_id_idx ON public.tab_ux_inform_log_p20260402 USING btree (id);


--
-- Name: tab_ux_inform_log_p20260402_serial_number_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260402_serial_number_idx ON public.tab_ux_inform_log_p20260402 USING btree (serial_number);


--
-- Name: tab_ux_inform_log_p20260403_create_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260403_create_time_idx ON public.tab_ux_inform_log_p20260403 USING btree (create_time);


--
-- Name: tab_ux_inform_log_p20260403_create_time_success_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260403_create_time_success_idx ON public.tab_ux_inform_log_p20260403 USING btree (create_time, success);


--
-- Name: tab_ux_inform_log_p20260403_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260403_id_idx ON public.tab_ux_inform_log_p20260403 USING btree (id);


--
-- Name: tab_ux_inform_log_p20260403_serial_number_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260403_serial_number_idx ON public.tab_ux_inform_log_p20260403 USING btree (serial_number);


--
-- Name: tab_ux_inform_log_p20260404_create_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260404_create_time_idx ON public.tab_ux_inform_log_p20260404 USING btree (create_time);


--
-- Name: tab_ux_inform_log_p20260404_create_time_success_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260404_create_time_success_idx ON public.tab_ux_inform_log_p20260404 USING btree (create_time, success);


--
-- Name: tab_ux_inform_log_p20260404_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260404_id_idx ON public.tab_ux_inform_log_p20260404 USING btree (id);


--
-- Name: tab_ux_inform_log_p20260404_serial_number_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260404_serial_number_idx ON public.tab_ux_inform_log_p20260404 USING btree (serial_number);


--
-- Name: tab_ux_inform_log_p20260405_create_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260405_create_time_idx ON public.tab_ux_inform_log_p20260405 USING btree (create_time);


--
-- Name: tab_ux_inform_log_p20260405_create_time_success_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260405_create_time_success_idx ON public.tab_ux_inform_log_p20260405 USING btree (create_time, success);


--
-- Name: tab_ux_inform_log_p20260405_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260405_id_idx ON public.tab_ux_inform_log_p20260405 USING btree (id);


--
-- Name: tab_ux_inform_log_p20260405_serial_number_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260405_serial_number_idx ON public.tab_ux_inform_log_p20260405 USING btree (serial_number);


--
-- Name: tab_ux_inform_log_p20260406_create_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260406_create_time_idx ON public.tab_ux_inform_log_p20260406 USING btree (create_time);


--
-- Name: tab_ux_inform_log_p20260406_create_time_success_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260406_create_time_success_idx ON public.tab_ux_inform_log_p20260406 USING btree (create_time, success);


--
-- Name: tab_ux_inform_log_p20260406_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260406_id_idx ON public.tab_ux_inform_log_p20260406 USING btree (id);


--
-- Name: tab_ux_inform_log_p20260406_serial_number_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260406_serial_number_idx ON public.tab_ux_inform_log_p20260406 USING btree (serial_number);


--
-- Name: tab_ux_inform_log_p20260407_create_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260407_create_time_idx ON public.tab_ux_inform_log_p20260407 USING btree (create_time);


--
-- Name: tab_ux_inform_log_p20260407_create_time_success_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260407_create_time_success_idx ON public.tab_ux_inform_log_p20260407 USING btree (create_time, success);


--
-- Name: tab_ux_inform_log_p20260407_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260407_id_idx ON public.tab_ux_inform_log_p20260407 USING btree (id);


--
-- Name: tab_ux_inform_log_p20260407_serial_number_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260407_serial_number_idx ON public.tab_ux_inform_log_p20260407 USING btree (serial_number);


--
-- Name: tab_ux_inform_log_p20260408_create_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260408_create_time_idx ON public.tab_ux_inform_log_p20260408 USING btree (create_time);


--
-- Name: tab_ux_inform_log_p20260408_create_time_success_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260408_create_time_success_idx ON public.tab_ux_inform_log_p20260408 USING btree (create_time, success);


--
-- Name: tab_ux_inform_log_p20260408_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260408_id_idx ON public.tab_ux_inform_log_p20260408 USING btree (id);


--
-- Name: tab_ux_inform_log_p20260408_serial_number_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260408_serial_number_idx ON public.tab_ux_inform_log_p20260408 USING btree (serial_number);


--
-- Name: tab_ux_inform_log_p20260409_create_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260409_create_time_idx ON public.tab_ux_inform_log_p20260409 USING btree (create_time);


--
-- Name: tab_ux_inform_log_p20260409_create_time_success_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260409_create_time_success_idx ON public.tab_ux_inform_log_p20260409 USING btree (create_time, success);


--
-- Name: tab_ux_inform_log_p20260409_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260409_id_idx ON public.tab_ux_inform_log_p20260409 USING btree (id);


--
-- Name: tab_ux_inform_log_p20260409_serial_number_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260409_serial_number_idx ON public.tab_ux_inform_log_p20260409 USING btree (serial_number);


--
-- Name: tab_ux_inform_log_p20260410_create_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260410_create_time_idx ON public.tab_ux_inform_log_p20260410 USING btree (create_time);


--
-- Name: tab_ux_inform_log_p20260410_create_time_success_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260410_create_time_success_idx ON public.tab_ux_inform_log_p20260410 USING btree (create_time, success);


--
-- Name: tab_ux_inform_log_p20260410_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260410_id_idx ON public.tab_ux_inform_log_p20260410 USING btree (id);


--
-- Name: tab_ux_inform_log_p20260410_serial_number_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260410_serial_number_idx ON public.tab_ux_inform_log_p20260410 USING btree (serial_number);


--
-- Name: tab_ux_inform_log_p20260411_create_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260411_create_time_idx ON public.tab_ux_inform_log_p20260411 USING btree (create_time);


--
-- Name: tab_ux_inform_log_p20260411_create_time_success_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260411_create_time_success_idx ON public.tab_ux_inform_log_p20260411 USING btree (create_time, success);


--
-- Name: tab_ux_inform_log_p20260411_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260411_id_idx ON public.tab_ux_inform_log_p20260411 USING btree (id);


--
-- Name: tab_ux_inform_log_p20260411_serial_number_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260411_serial_number_idx ON public.tab_ux_inform_log_p20260411 USING btree (serial_number);


--
-- Name: tab_ux_inform_log_p20260412_create_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260412_create_time_idx ON public.tab_ux_inform_log_p20260412 USING btree (create_time);


--
-- Name: tab_ux_inform_log_p20260412_create_time_success_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260412_create_time_success_idx ON public.tab_ux_inform_log_p20260412 USING btree (create_time, success);


--
-- Name: tab_ux_inform_log_p20260412_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260412_id_idx ON public.tab_ux_inform_log_p20260412 USING btree (id);


--
-- Name: tab_ux_inform_log_p20260412_serial_number_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260412_serial_number_idx ON public.tab_ux_inform_log_p20260412 USING btree (serial_number);


--
-- Name: tab_ux_inform_log_p20260413_create_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260413_create_time_idx ON public.tab_ux_inform_log_p20260413 USING btree (create_time);


--
-- Name: tab_ux_inform_log_p20260413_create_time_success_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260413_create_time_success_idx ON public.tab_ux_inform_log_p20260413 USING btree (create_time, success);


--
-- Name: tab_ux_inform_log_p20260413_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260413_id_idx ON public.tab_ux_inform_log_p20260413 USING btree (id);


--
-- Name: tab_ux_inform_log_p20260413_serial_number_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260413_serial_number_idx ON public.tab_ux_inform_log_p20260413 USING btree (serial_number);


--
-- Name: tab_ux_inform_log_p20260414_create_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260414_create_time_idx ON public.tab_ux_inform_log_p20260414 USING btree (create_time);


--
-- Name: tab_ux_inform_log_p20260414_create_time_success_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260414_create_time_success_idx ON public.tab_ux_inform_log_p20260414 USING btree (create_time, success);


--
-- Name: tab_ux_inform_log_p20260414_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260414_id_idx ON public.tab_ux_inform_log_p20260414 USING btree (id);


--
-- Name: tab_ux_inform_log_p20260414_serial_number_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260414_serial_number_idx ON public.tab_ux_inform_log_p20260414 USING btree (serial_number);


--
-- Name: tab_ux_inform_log_p20260415_create_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260415_create_time_idx ON public.tab_ux_inform_log_p20260415 USING btree (create_time);


--
-- Name: tab_ux_inform_log_p20260415_create_time_success_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260415_create_time_success_idx ON public.tab_ux_inform_log_p20260415 USING btree (create_time, success);


--
-- Name: tab_ux_inform_log_p20260415_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260415_id_idx ON public.tab_ux_inform_log_p20260415 USING btree (id);


--
-- Name: tab_ux_inform_log_p20260415_serial_number_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260415_serial_number_idx ON public.tab_ux_inform_log_p20260415 USING btree (serial_number);


--
-- Name: tab_ux_inform_log_p20260416_create_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260416_create_time_idx ON public.tab_ux_inform_log_p20260416 USING btree (create_time);


--
-- Name: tab_ux_inform_log_p20260416_create_time_success_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260416_create_time_success_idx ON public.tab_ux_inform_log_p20260416 USING btree (create_time, success);


--
-- Name: tab_ux_inform_log_p20260416_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260416_id_idx ON public.tab_ux_inform_log_p20260416 USING btree (id);


--
-- Name: tab_ux_inform_log_p20260416_serial_number_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260416_serial_number_idx ON public.tab_ux_inform_log_p20260416 USING btree (serial_number);


--
-- Name: tab_ux_inform_log_p20260417_create_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260417_create_time_idx ON public.tab_ux_inform_log_p20260417 USING btree (create_time);


--
-- Name: tab_ux_inform_log_p20260417_create_time_success_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260417_create_time_success_idx ON public.tab_ux_inform_log_p20260417 USING btree (create_time, success);


--
-- Name: tab_ux_inform_log_p20260417_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260417_id_idx ON public.tab_ux_inform_log_p20260417 USING btree (id);


--
-- Name: tab_ux_inform_log_p20260417_serial_number_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260417_serial_number_idx ON public.tab_ux_inform_log_p20260417 USING btree (serial_number);


--
-- Name: tab_ux_inform_log_p20260418_create_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260418_create_time_idx ON public.tab_ux_inform_log_p20260418 USING btree (create_time);


--
-- Name: tab_ux_inform_log_p20260418_create_time_success_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260418_create_time_success_idx ON public.tab_ux_inform_log_p20260418 USING btree (create_time, success);


--
-- Name: tab_ux_inform_log_p20260418_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260418_id_idx ON public.tab_ux_inform_log_p20260418 USING btree (id);


--
-- Name: tab_ux_inform_log_p20260418_serial_number_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260418_serial_number_idx ON public.tab_ux_inform_log_p20260418 USING btree (serial_number);


--
-- Name: tab_ux_inform_log_p20260419_create_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260419_create_time_idx ON public.tab_ux_inform_log_p20260419 USING btree (create_time);


--
-- Name: tab_ux_inform_log_p20260419_create_time_success_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260419_create_time_success_idx ON public.tab_ux_inform_log_p20260419 USING btree (create_time, success);


--
-- Name: tab_ux_inform_log_p20260419_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260419_id_idx ON public.tab_ux_inform_log_p20260419 USING btree (id);


--
-- Name: tab_ux_inform_log_p20260419_serial_number_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260419_serial_number_idx ON public.tab_ux_inform_log_p20260419 USING btree (serial_number);


--
-- Name: tab_ux_inform_log_p20260420_create_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260420_create_time_idx ON public.tab_ux_inform_log_p20260420 USING btree (create_time);


--
-- Name: tab_ux_inform_log_p20260420_create_time_success_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260420_create_time_success_idx ON public.tab_ux_inform_log_p20260420 USING btree (create_time, success);


--
-- Name: tab_ux_inform_log_p20260420_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260420_id_idx ON public.tab_ux_inform_log_p20260420 USING btree (id);


--
-- Name: tab_ux_inform_log_p20260420_serial_number_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260420_serial_number_idx ON public.tab_ux_inform_log_p20260420 USING btree (serial_number);


--
-- Name: tab_ux_inform_log_p20260421_create_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260421_create_time_idx ON public.tab_ux_inform_log_p20260421 USING btree (create_time);


--
-- Name: tab_ux_inform_log_p20260421_create_time_success_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260421_create_time_success_idx ON public.tab_ux_inform_log_p20260421 USING btree (create_time, success);


--
-- Name: tab_ux_inform_log_p20260421_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260421_id_idx ON public.tab_ux_inform_log_p20260421 USING btree (id);


--
-- Name: tab_ux_inform_log_p20260421_serial_number_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260421_serial_number_idx ON public.tab_ux_inform_log_p20260421 USING btree (serial_number);


--
-- Name: tab_ux_inform_log_p20260422_create_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260422_create_time_idx ON public.tab_ux_inform_log_p20260422 USING btree (create_time);


--
-- Name: tab_ux_inform_log_p20260422_create_time_success_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260422_create_time_success_idx ON public.tab_ux_inform_log_p20260422 USING btree (create_time, success);


--
-- Name: tab_ux_inform_log_p20260422_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260422_id_idx ON public.tab_ux_inform_log_p20260422 USING btree (id);


--
-- Name: tab_ux_inform_log_p20260422_serial_number_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260422_serial_number_idx ON public.tab_ux_inform_log_p20260422 USING btree (serial_number);


--
-- Name: tab_ux_inform_log_p20260423_create_time_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260423_create_time_idx ON public.tab_ux_inform_log_p20260423 USING btree (create_time);


--
-- Name: tab_ux_inform_log_p20260423_create_time_success_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260423_create_time_success_idx ON public.tab_ux_inform_log_p20260423 USING btree (create_time, success);


--
-- Name: tab_ux_inform_log_p20260423_id_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260423_id_idx ON public.tab_ux_inform_log_p20260423 USING btree (id);


--
-- Name: tab_ux_inform_log_p20260423_serial_number_idx; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE INDEX tab_ux_inform_log_p20260423_serial_number_idx ON public.tab_ux_inform_log_p20260423 USING btree (serial_number);


--
-- Name: u_area_name; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE UNIQUE INDEX u_area_name ON public.tab_area USING btree (area_name);


--
-- Name: u_init_oui_sn; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE UNIQUE INDEX u_init_oui_sn ON public.tab_gw_device_init USING btree (oui, device_serialnumber);


--
-- Name: u_offe_name; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE UNIQUE INDEX u_offe_name ON public.tab_office USING btree (office_name);


--
-- Name: u_oui_sn; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE UNIQUE INDEX u_oui_sn ON public.tab_gw_device USING btree (oui, device_serialnumber);


--
-- Name: u_type_name; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE UNIQUE INDEX u_type_name ON public.gw_dev_type USING btree (type_name);


--
-- Name: u_username; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE UNIQUE INDEX u_username ON public.itv_customer_info USING btree (username);


--
-- Name: uk_sd_dict_code; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE UNIQUE INDEX uk_sd_dict_code ON public.sys_dict USING btree (dict_code);


--
-- Name: uk_sdc_rule_code; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE UNIQUE INDEX uk_sdc_rule_code ON public.sys_data_source USING btree (code);


--
-- Name: uk_sfr_rule_code; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE UNIQUE INDEX uk_sfr_rule_code ON public.sys_fill_rule USING btree (rule_code);


--
-- Name: uk_sst_template_code; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE UNIQUE INDEX uk_sst_template_code ON public.sys_sms_template USING btree (template_code);


--
-- Name: uniq_depart_org_code; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE UNIQUE INDEX uniq_depart_org_code ON public.sys_depart USING btree (org_code);


--
-- Name: uniq_position_code; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE UNIQUE INDEX uniq_position_code ON public.sys_position USING btree (code);


--
-- Name: uniq_sys_role_role_code; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE UNIQUE INDEX uniq_sys_role_role_code ON public.sys_role USING btree (role_code);


--
-- Name: uniq_sys_user_email; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE UNIQUE INDEX uniq_sys_user_email ON public.sys_user USING btree (email);


--
-- Name: uniq_sys_user_phone; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE UNIQUE INDEX uniq_sys_user_phone ON public.sys_user USING btree (phone);


--
-- Name: uniq_sys_user_username; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE UNIQUE INDEX uniq_sys_user_username ON public.sys_user USING btree (username);


--
-- Name: uniq_sys_user_work_no; Type: INDEX; Schema: public; Owner: gtmsmanager
--

CREATE UNIQUE INDEX uniq_sys_user_work_no ON public.sys_user USING btree (work_no);


--
-- Name: tab_capacity_log_default_call_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_call_id ATTACH PARTITION public.tab_capacity_log_default_call_id_idx;


--
-- Name: tab_capacity_log_default_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_call_time ATTACH PARTITION public.tab_capacity_log_default_call_time_idx;


--
-- Name: tab_capacity_log_default_device_type_rpc_type_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_device_rpc_time ATTACH PARTITION public.tab_capacity_log_default_device_type_rpc_type_call_time_idx;


--
-- Name: tab_capacity_log_default_serial_number_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_serial_number ATTACH PARTITION public.tab_capacity_log_default_serial_number_idx;


--
-- Name: tab_capacity_log_p20260323_call_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_call_id ATTACH PARTITION public.tab_capacity_log_p20260323_call_id_idx;


--
-- Name: tab_capacity_log_p20260323_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_call_time ATTACH PARTITION public.tab_capacity_log_p20260323_call_time_idx;


--
-- Name: tab_capacity_log_p20260323_device_type_rpc_type_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_device_rpc_time ATTACH PARTITION public.tab_capacity_log_p20260323_device_type_rpc_type_call_time_idx;


--
-- Name: tab_capacity_log_p20260323_serial_number_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_serial_number ATTACH PARTITION public.tab_capacity_log_p20260323_serial_number_idx;


--
-- Name: tab_capacity_log_p20260324_call_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_call_id ATTACH PARTITION public.tab_capacity_log_p20260324_call_id_idx;


--
-- Name: tab_capacity_log_p20260324_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_call_time ATTACH PARTITION public.tab_capacity_log_p20260324_call_time_idx;


--
-- Name: tab_capacity_log_p20260324_device_type_rpc_type_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_device_rpc_time ATTACH PARTITION public.tab_capacity_log_p20260324_device_type_rpc_type_call_time_idx;


--
-- Name: tab_capacity_log_p20260324_serial_number_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_serial_number ATTACH PARTITION public.tab_capacity_log_p20260324_serial_number_idx;


--
-- Name: tab_capacity_log_p20260325_call_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_call_id ATTACH PARTITION public.tab_capacity_log_p20260325_call_id_idx;


--
-- Name: tab_capacity_log_p20260325_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_call_time ATTACH PARTITION public.tab_capacity_log_p20260325_call_time_idx;


--
-- Name: tab_capacity_log_p20260325_device_type_rpc_type_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_device_rpc_time ATTACH PARTITION public.tab_capacity_log_p20260325_device_type_rpc_type_call_time_idx;


--
-- Name: tab_capacity_log_p20260325_serial_number_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_serial_number ATTACH PARTITION public.tab_capacity_log_p20260325_serial_number_idx;


--
-- Name: tab_capacity_log_p20260326_call_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_call_id ATTACH PARTITION public.tab_capacity_log_p20260326_call_id_idx;


--
-- Name: tab_capacity_log_p20260326_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_call_time ATTACH PARTITION public.tab_capacity_log_p20260326_call_time_idx;


--
-- Name: tab_capacity_log_p20260326_device_type_rpc_type_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_device_rpc_time ATTACH PARTITION public.tab_capacity_log_p20260326_device_type_rpc_type_call_time_idx;


--
-- Name: tab_capacity_log_p20260326_serial_number_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_serial_number ATTACH PARTITION public.tab_capacity_log_p20260326_serial_number_idx;


--
-- Name: tab_capacity_log_p20260327_call_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_call_id ATTACH PARTITION public.tab_capacity_log_p20260327_call_id_idx;


--
-- Name: tab_capacity_log_p20260327_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_call_time ATTACH PARTITION public.tab_capacity_log_p20260327_call_time_idx;


--
-- Name: tab_capacity_log_p20260327_device_type_rpc_type_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_device_rpc_time ATTACH PARTITION public.tab_capacity_log_p20260327_device_type_rpc_type_call_time_idx;


--
-- Name: tab_capacity_log_p20260327_serial_number_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_serial_number ATTACH PARTITION public.tab_capacity_log_p20260327_serial_number_idx;


--
-- Name: tab_capacity_log_p20260328_call_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_call_id ATTACH PARTITION public.tab_capacity_log_p20260328_call_id_idx;


--
-- Name: tab_capacity_log_p20260328_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_call_time ATTACH PARTITION public.tab_capacity_log_p20260328_call_time_idx;


--
-- Name: tab_capacity_log_p20260328_device_type_rpc_type_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_device_rpc_time ATTACH PARTITION public.tab_capacity_log_p20260328_device_type_rpc_type_call_time_idx;


--
-- Name: tab_capacity_log_p20260328_serial_number_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_serial_number ATTACH PARTITION public.tab_capacity_log_p20260328_serial_number_idx;


--
-- Name: tab_capacity_log_p20260329_call_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_call_id ATTACH PARTITION public.tab_capacity_log_p20260329_call_id_idx;


--
-- Name: tab_capacity_log_p20260329_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_call_time ATTACH PARTITION public.tab_capacity_log_p20260329_call_time_idx;


--
-- Name: tab_capacity_log_p20260329_device_type_rpc_type_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_device_rpc_time ATTACH PARTITION public.tab_capacity_log_p20260329_device_type_rpc_type_call_time_idx;


--
-- Name: tab_capacity_log_p20260329_serial_number_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_serial_number ATTACH PARTITION public.tab_capacity_log_p20260329_serial_number_idx;


--
-- Name: tab_capacity_log_p20260330_call_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_call_id ATTACH PARTITION public.tab_capacity_log_p20260330_call_id_idx;


--
-- Name: tab_capacity_log_p20260330_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_call_time ATTACH PARTITION public.tab_capacity_log_p20260330_call_time_idx;


--
-- Name: tab_capacity_log_p20260330_device_type_rpc_type_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_device_rpc_time ATTACH PARTITION public.tab_capacity_log_p20260330_device_type_rpc_type_call_time_idx;


--
-- Name: tab_capacity_log_p20260330_serial_number_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_serial_number ATTACH PARTITION public.tab_capacity_log_p20260330_serial_number_idx;


--
-- Name: tab_capacity_log_p20260331_call_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_call_id ATTACH PARTITION public.tab_capacity_log_p20260331_call_id_idx;


--
-- Name: tab_capacity_log_p20260331_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_call_time ATTACH PARTITION public.tab_capacity_log_p20260331_call_time_idx;


--
-- Name: tab_capacity_log_p20260331_device_type_rpc_type_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_device_rpc_time ATTACH PARTITION public.tab_capacity_log_p20260331_device_type_rpc_type_call_time_idx;


--
-- Name: tab_capacity_log_p20260331_serial_number_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_serial_number ATTACH PARTITION public.tab_capacity_log_p20260331_serial_number_idx;


--
-- Name: tab_capacity_log_p20260401_call_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_call_id ATTACH PARTITION public.tab_capacity_log_p20260401_call_id_idx;


--
-- Name: tab_capacity_log_p20260401_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_call_time ATTACH PARTITION public.tab_capacity_log_p20260401_call_time_idx;


--
-- Name: tab_capacity_log_p20260401_device_type_rpc_type_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_device_rpc_time ATTACH PARTITION public.tab_capacity_log_p20260401_device_type_rpc_type_call_time_idx;


--
-- Name: tab_capacity_log_p20260401_serial_number_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_serial_number ATTACH PARTITION public.tab_capacity_log_p20260401_serial_number_idx;


--
-- Name: tab_capacity_log_p20260402_call_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_call_id ATTACH PARTITION public.tab_capacity_log_p20260402_call_id_idx;


--
-- Name: tab_capacity_log_p20260402_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_call_time ATTACH PARTITION public.tab_capacity_log_p20260402_call_time_idx;


--
-- Name: tab_capacity_log_p20260402_device_type_rpc_type_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_device_rpc_time ATTACH PARTITION public.tab_capacity_log_p20260402_device_type_rpc_type_call_time_idx;


--
-- Name: tab_capacity_log_p20260402_serial_number_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_serial_number ATTACH PARTITION public.tab_capacity_log_p20260402_serial_number_idx;


--
-- Name: tab_capacity_log_p20260403_call_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_call_id ATTACH PARTITION public.tab_capacity_log_p20260403_call_id_idx;


--
-- Name: tab_capacity_log_p20260403_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_call_time ATTACH PARTITION public.tab_capacity_log_p20260403_call_time_idx;


--
-- Name: tab_capacity_log_p20260403_device_type_rpc_type_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_device_rpc_time ATTACH PARTITION public.tab_capacity_log_p20260403_device_type_rpc_type_call_time_idx;


--
-- Name: tab_capacity_log_p20260403_serial_number_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_serial_number ATTACH PARTITION public.tab_capacity_log_p20260403_serial_number_idx;


--
-- Name: tab_capacity_log_p20260404_call_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_call_id ATTACH PARTITION public.tab_capacity_log_p20260404_call_id_idx;


--
-- Name: tab_capacity_log_p20260404_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_call_time ATTACH PARTITION public.tab_capacity_log_p20260404_call_time_idx;


--
-- Name: tab_capacity_log_p20260404_device_type_rpc_type_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_device_rpc_time ATTACH PARTITION public.tab_capacity_log_p20260404_device_type_rpc_type_call_time_idx;


--
-- Name: tab_capacity_log_p20260404_serial_number_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_serial_number ATTACH PARTITION public.tab_capacity_log_p20260404_serial_number_idx;


--
-- Name: tab_capacity_log_p20260405_call_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_call_id ATTACH PARTITION public.tab_capacity_log_p20260405_call_id_idx;


--
-- Name: tab_capacity_log_p20260405_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_call_time ATTACH PARTITION public.tab_capacity_log_p20260405_call_time_idx;


--
-- Name: tab_capacity_log_p20260405_device_type_rpc_type_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_device_rpc_time ATTACH PARTITION public.tab_capacity_log_p20260405_device_type_rpc_type_call_time_idx;


--
-- Name: tab_capacity_log_p20260405_serial_number_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_serial_number ATTACH PARTITION public.tab_capacity_log_p20260405_serial_number_idx;


--
-- Name: tab_capacity_log_p20260406_call_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_call_id ATTACH PARTITION public.tab_capacity_log_p20260406_call_id_idx;


--
-- Name: tab_capacity_log_p20260406_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_call_time ATTACH PARTITION public.tab_capacity_log_p20260406_call_time_idx;


--
-- Name: tab_capacity_log_p20260406_device_type_rpc_type_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_device_rpc_time ATTACH PARTITION public.tab_capacity_log_p20260406_device_type_rpc_type_call_time_idx;


--
-- Name: tab_capacity_log_p20260406_serial_number_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_serial_number ATTACH PARTITION public.tab_capacity_log_p20260406_serial_number_idx;


--
-- Name: tab_capacity_log_p20260407_call_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_call_id ATTACH PARTITION public.tab_capacity_log_p20260407_call_id_idx;


--
-- Name: tab_capacity_log_p20260407_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_call_time ATTACH PARTITION public.tab_capacity_log_p20260407_call_time_idx;


--
-- Name: tab_capacity_log_p20260407_device_type_rpc_type_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_device_rpc_time ATTACH PARTITION public.tab_capacity_log_p20260407_device_type_rpc_type_call_time_idx;


--
-- Name: tab_capacity_log_p20260407_serial_number_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_serial_number ATTACH PARTITION public.tab_capacity_log_p20260407_serial_number_idx;


--
-- Name: tab_capacity_log_p20260408_call_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_call_id ATTACH PARTITION public.tab_capacity_log_p20260408_call_id_idx;


--
-- Name: tab_capacity_log_p20260408_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_call_time ATTACH PARTITION public.tab_capacity_log_p20260408_call_time_idx;


--
-- Name: tab_capacity_log_p20260408_device_type_rpc_type_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_device_rpc_time ATTACH PARTITION public.tab_capacity_log_p20260408_device_type_rpc_type_call_time_idx;


--
-- Name: tab_capacity_log_p20260408_serial_number_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_serial_number ATTACH PARTITION public.tab_capacity_log_p20260408_serial_number_idx;


--
-- Name: tab_capacity_log_p20260409_call_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_call_id ATTACH PARTITION public.tab_capacity_log_p20260409_call_id_idx;


--
-- Name: tab_capacity_log_p20260409_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_call_time ATTACH PARTITION public.tab_capacity_log_p20260409_call_time_idx;


--
-- Name: tab_capacity_log_p20260409_device_type_rpc_type_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_device_rpc_time ATTACH PARTITION public.tab_capacity_log_p20260409_device_type_rpc_type_call_time_idx;


--
-- Name: tab_capacity_log_p20260409_serial_number_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_serial_number ATTACH PARTITION public.tab_capacity_log_p20260409_serial_number_idx;


--
-- Name: tab_capacity_log_p20260410_call_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_call_id ATTACH PARTITION public.tab_capacity_log_p20260410_call_id_idx;


--
-- Name: tab_capacity_log_p20260410_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_call_time ATTACH PARTITION public.tab_capacity_log_p20260410_call_time_idx;


--
-- Name: tab_capacity_log_p20260410_device_type_rpc_type_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_device_rpc_time ATTACH PARTITION public.tab_capacity_log_p20260410_device_type_rpc_type_call_time_idx;


--
-- Name: tab_capacity_log_p20260410_serial_number_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_serial_number ATTACH PARTITION public.tab_capacity_log_p20260410_serial_number_idx;


--
-- Name: tab_capacity_log_p20260411_call_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_call_id ATTACH PARTITION public.tab_capacity_log_p20260411_call_id_idx;


--
-- Name: tab_capacity_log_p20260411_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_call_time ATTACH PARTITION public.tab_capacity_log_p20260411_call_time_idx;


--
-- Name: tab_capacity_log_p20260411_device_type_rpc_type_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_device_rpc_time ATTACH PARTITION public.tab_capacity_log_p20260411_device_type_rpc_type_call_time_idx;


--
-- Name: tab_capacity_log_p20260411_serial_number_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_serial_number ATTACH PARTITION public.tab_capacity_log_p20260411_serial_number_idx;


--
-- Name: tab_capacity_log_p20260412_call_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_call_id ATTACH PARTITION public.tab_capacity_log_p20260412_call_id_idx;


--
-- Name: tab_capacity_log_p20260412_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_call_time ATTACH PARTITION public.tab_capacity_log_p20260412_call_time_idx;


--
-- Name: tab_capacity_log_p20260412_device_type_rpc_type_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_device_rpc_time ATTACH PARTITION public.tab_capacity_log_p20260412_device_type_rpc_type_call_time_idx;


--
-- Name: tab_capacity_log_p20260412_serial_number_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_serial_number ATTACH PARTITION public.tab_capacity_log_p20260412_serial_number_idx;


--
-- Name: tab_capacity_log_p20260413_call_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_call_id ATTACH PARTITION public.tab_capacity_log_p20260413_call_id_idx;


--
-- Name: tab_capacity_log_p20260413_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_call_time ATTACH PARTITION public.tab_capacity_log_p20260413_call_time_idx;


--
-- Name: tab_capacity_log_p20260413_device_type_rpc_type_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_device_rpc_time ATTACH PARTITION public.tab_capacity_log_p20260413_device_type_rpc_type_call_time_idx;


--
-- Name: tab_capacity_log_p20260413_serial_number_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_serial_number ATTACH PARTITION public.tab_capacity_log_p20260413_serial_number_idx;


--
-- Name: tab_capacity_log_p20260414_call_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_call_id ATTACH PARTITION public.tab_capacity_log_p20260414_call_id_idx;


--
-- Name: tab_capacity_log_p20260414_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_call_time ATTACH PARTITION public.tab_capacity_log_p20260414_call_time_idx;


--
-- Name: tab_capacity_log_p20260414_device_type_rpc_type_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_device_rpc_time ATTACH PARTITION public.tab_capacity_log_p20260414_device_type_rpc_type_call_time_idx;


--
-- Name: tab_capacity_log_p20260414_serial_number_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_serial_number ATTACH PARTITION public.tab_capacity_log_p20260414_serial_number_idx;


--
-- Name: tab_capacity_log_p20260415_call_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_call_id ATTACH PARTITION public.tab_capacity_log_p20260415_call_id_idx;


--
-- Name: tab_capacity_log_p20260415_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_call_time ATTACH PARTITION public.tab_capacity_log_p20260415_call_time_idx;


--
-- Name: tab_capacity_log_p20260415_device_type_rpc_type_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_device_rpc_time ATTACH PARTITION public.tab_capacity_log_p20260415_device_type_rpc_type_call_time_idx;


--
-- Name: tab_capacity_log_p20260415_serial_number_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_serial_number ATTACH PARTITION public.tab_capacity_log_p20260415_serial_number_idx;


--
-- Name: tab_capacity_log_p20260416_call_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_call_id ATTACH PARTITION public.tab_capacity_log_p20260416_call_id_idx;


--
-- Name: tab_capacity_log_p20260416_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_call_time ATTACH PARTITION public.tab_capacity_log_p20260416_call_time_idx;


--
-- Name: tab_capacity_log_p20260416_device_type_rpc_type_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_device_rpc_time ATTACH PARTITION public.tab_capacity_log_p20260416_device_type_rpc_type_call_time_idx;


--
-- Name: tab_capacity_log_p20260416_serial_number_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_serial_number ATTACH PARTITION public.tab_capacity_log_p20260416_serial_number_idx;


--
-- Name: tab_capacity_log_p20260417_call_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_call_id ATTACH PARTITION public.tab_capacity_log_p20260417_call_id_idx;


--
-- Name: tab_capacity_log_p20260417_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_call_time ATTACH PARTITION public.tab_capacity_log_p20260417_call_time_idx;


--
-- Name: tab_capacity_log_p20260417_device_type_rpc_type_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_device_rpc_time ATTACH PARTITION public.tab_capacity_log_p20260417_device_type_rpc_type_call_time_idx;


--
-- Name: tab_capacity_log_p20260417_serial_number_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_serial_number ATTACH PARTITION public.tab_capacity_log_p20260417_serial_number_idx;


--
-- Name: tab_capacity_log_p20260418_call_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_call_id ATTACH PARTITION public.tab_capacity_log_p20260418_call_id_idx;


--
-- Name: tab_capacity_log_p20260418_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_call_time ATTACH PARTITION public.tab_capacity_log_p20260418_call_time_idx;


--
-- Name: tab_capacity_log_p20260418_device_type_rpc_type_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_device_rpc_time ATTACH PARTITION public.tab_capacity_log_p20260418_device_type_rpc_type_call_time_idx;


--
-- Name: tab_capacity_log_p20260418_serial_number_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_serial_number ATTACH PARTITION public.tab_capacity_log_p20260418_serial_number_idx;


--
-- Name: tab_capacity_log_p20260419_call_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_call_id ATTACH PARTITION public.tab_capacity_log_p20260419_call_id_idx;


--
-- Name: tab_capacity_log_p20260419_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_call_time ATTACH PARTITION public.tab_capacity_log_p20260419_call_time_idx;


--
-- Name: tab_capacity_log_p20260419_device_type_rpc_type_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_device_rpc_time ATTACH PARTITION public.tab_capacity_log_p20260419_device_type_rpc_type_call_time_idx;


--
-- Name: tab_capacity_log_p20260419_serial_number_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_serial_number ATTACH PARTITION public.tab_capacity_log_p20260419_serial_number_idx;


--
-- Name: tab_capacity_log_p20260420_call_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_call_id ATTACH PARTITION public.tab_capacity_log_p20260420_call_id_idx;


--
-- Name: tab_capacity_log_p20260420_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_call_time ATTACH PARTITION public.tab_capacity_log_p20260420_call_time_idx;


--
-- Name: tab_capacity_log_p20260420_device_type_rpc_type_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_device_rpc_time ATTACH PARTITION public.tab_capacity_log_p20260420_device_type_rpc_type_call_time_idx;


--
-- Name: tab_capacity_log_p20260420_serial_number_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_serial_number ATTACH PARTITION public.tab_capacity_log_p20260420_serial_number_idx;


--
-- Name: tab_capacity_log_p20260421_call_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_call_id ATTACH PARTITION public.tab_capacity_log_p20260421_call_id_idx;


--
-- Name: tab_capacity_log_p20260421_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_call_time ATTACH PARTITION public.tab_capacity_log_p20260421_call_time_idx;


--
-- Name: tab_capacity_log_p20260421_device_type_rpc_type_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_device_rpc_time ATTACH PARTITION public.tab_capacity_log_p20260421_device_type_rpc_type_call_time_idx;


--
-- Name: tab_capacity_log_p20260421_serial_number_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_serial_number ATTACH PARTITION public.tab_capacity_log_p20260421_serial_number_idx;


--
-- Name: tab_capacity_log_p20260422_call_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_call_id ATTACH PARTITION public.tab_capacity_log_p20260422_call_id_idx;


--
-- Name: tab_capacity_log_p20260422_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_call_time ATTACH PARTITION public.tab_capacity_log_p20260422_call_time_idx;


--
-- Name: tab_capacity_log_p20260422_device_type_rpc_type_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_device_rpc_time ATTACH PARTITION public.tab_capacity_log_p20260422_device_type_rpc_type_call_time_idx;


--
-- Name: tab_capacity_log_p20260422_serial_number_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_serial_number ATTACH PARTITION public.tab_capacity_log_p20260422_serial_number_idx;


--
-- Name: tab_capacity_log_p20260423_call_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_call_id ATTACH PARTITION public.tab_capacity_log_p20260423_call_id_idx;


--
-- Name: tab_capacity_log_p20260423_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_call_time ATTACH PARTITION public.tab_capacity_log_p20260423_call_time_idx;


--
-- Name: tab_capacity_log_p20260423_device_type_rpc_type_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_device_rpc_time ATTACH PARTITION public.tab_capacity_log_p20260423_device_type_rpc_type_call_time_idx;


--
-- Name: tab_capacity_log_p20260423_serial_number_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_p_serial_number ATTACH PARTITION public.tab_capacity_log_p20260423_serial_number_idx;


--
-- Name: tab_capacity_log_parameter_default_call_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_parameter_p_call_id ATTACH PARTITION public.tab_capacity_log_parameter_default_call_id_idx;


--
-- Name: tab_capacity_log_parameter_default_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_parameter_p_call_time ATTACH PARTITION public.tab_capacity_log_parameter_default_call_time_idx;


--
-- Name: tab_capacity_log_parameter_p20260323_call_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_parameter_p_call_id ATTACH PARTITION public.tab_capacity_log_parameter_p20260323_call_id_idx;


--
-- Name: tab_capacity_log_parameter_p20260323_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_parameter_p_call_time ATTACH PARTITION public.tab_capacity_log_parameter_p20260323_call_time_idx;


--
-- Name: tab_capacity_log_parameter_p20260324_call_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_parameter_p_call_id ATTACH PARTITION public.tab_capacity_log_parameter_p20260324_call_id_idx;


--
-- Name: tab_capacity_log_parameter_p20260324_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_parameter_p_call_time ATTACH PARTITION public.tab_capacity_log_parameter_p20260324_call_time_idx;


--
-- Name: tab_capacity_log_parameter_p20260325_call_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_parameter_p_call_id ATTACH PARTITION public.tab_capacity_log_parameter_p20260325_call_id_idx;


--
-- Name: tab_capacity_log_parameter_p20260325_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_parameter_p_call_time ATTACH PARTITION public.tab_capacity_log_parameter_p20260325_call_time_idx;


--
-- Name: tab_capacity_log_parameter_p20260326_call_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_parameter_p_call_id ATTACH PARTITION public.tab_capacity_log_parameter_p20260326_call_id_idx;


--
-- Name: tab_capacity_log_parameter_p20260326_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_parameter_p_call_time ATTACH PARTITION public.tab_capacity_log_parameter_p20260326_call_time_idx;


--
-- Name: tab_capacity_log_parameter_p20260327_call_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_parameter_p_call_id ATTACH PARTITION public.tab_capacity_log_parameter_p20260327_call_id_idx;


--
-- Name: tab_capacity_log_parameter_p20260327_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_parameter_p_call_time ATTACH PARTITION public.tab_capacity_log_parameter_p20260327_call_time_idx;


--
-- Name: tab_capacity_log_parameter_p20260328_call_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_parameter_p_call_id ATTACH PARTITION public.tab_capacity_log_parameter_p20260328_call_id_idx;


--
-- Name: tab_capacity_log_parameter_p20260328_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_parameter_p_call_time ATTACH PARTITION public.tab_capacity_log_parameter_p20260328_call_time_idx;


--
-- Name: tab_capacity_log_parameter_p20260329_call_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_parameter_p_call_id ATTACH PARTITION public.tab_capacity_log_parameter_p20260329_call_id_idx;


--
-- Name: tab_capacity_log_parameter_p20260329_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_parameter_p_call_time ATTACH PARTITION public.tab_capacity_log_parameter_p20260329_call_time_idx;


--
-- Name: tab_capacity_log_parameter_p20260330_call_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_parameter_p_call_id ATTACH PARTITION public.tab_capacity_log_parameter_p20260330_call_id_idx;


--
-- Name: tab_capacity_log_parameter_p20260330_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_parameter_p_call_time ATTACH PARTITION public.tab_capacity_log_parameter_p20260330_call_time_idx;


--
-- Name: tab_capacity_log_parameter_p20260331_call_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_parameter_p_call_id ATTACH PARTITION public.tab_capacity_log_parameter_p20260331_call_id_idx;


--
-- Name: tab_capacity_log_parameter_p20260331_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_parameter_p_call_time ATTACH PARTITION public.tab_capacity_log_parameter_p20260331_call_time_idx;


--
-- Name: tab_capacity_log_parameter_p20260401_call_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_parameter_p_call_id ATTACH PARTITION public.tab_capacity_log_parameter_p20260401_call_id_idx;


--
-- Name: tab_capacity_log_parameter_p20260401_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_parameter_p_call_time ATTACH PARTITION public.tab_capacity_log_parameter_p20260401_call_time_idx;


--
-- Name: tab_capacity_log_parameter_p20260402_call_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_parameter_p_call_id ATTACH PARTITION public.tab_capacity_log_parameter_p20260402_call_id_idx;


--
-- Name: tab_capacity_log_parameter_p20260402_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_parameter_p_call_time ATTACH PARTITION public.tab_capacity_log_parameter_p20260402_call_time_idx;


--
-- Name: tab_capacity_log_parameter_p20260403_call_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_parameter_p_call_id ATTACH PARTITION public.tab_capacity_log_parameter_p20260403_call_id_idx;


--
-- Name: tab_capacity_log_parameter_p20260403_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_parameter_p_call_time ATTACH PARTITION public.tab_capacity_log_parameter_p20260403_call_time_idx;


--
-- Name: tab_capacity_log_parameter_p20260404_call_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_parameter_p_call_id ATTACH PARTITION public.tab_capacity_log_parameter_p20260404_call_id_idx;


--
-- Name: tab_capacity_log_parameter_p20260404_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_parameter_p_call_time ATTACH PARTITION public.tab_capacity_log_parameter_p20260404_call_time_idx;


--
-- Name: tab_capacity_log_parameter_p20260405_call_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_parameter_p_call_id ATTACH PARTITION public.tab_capacity_log_parameter_p20260405_call_id_idx;


--
-- Name: tab_capacity_log_parameter_p20260405_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_parameter_p_call_time ATTACH PARTITION public.tab_capacity_log_parameter_p20260405_call_time_idx;


--
-- Name: tab_capacity_log_parameter_p20260406_call_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_parameter_p_call_id ATTACH PARTITION public.tab_capacity_log_parameter_p20260406_call_id_idx;


--
-- Name: tab_capacity_log_parameter_p20260406_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_parameter_p_call_time ATTACH PARTITION public.tab_capacity_log_parameter_p20260406_call_time_idx;


--
-- Name: tab_capacity_log_parameter_p20260407_call_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_parameter_p_call_id ATTACH PARTITION public.tab_capacity_log_parameter_p20260407_call_id_idx;


--
-- Name: tab_capacity_log_parameter_p20260407_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_parameter_p_call_time ATTACH PARTITION public.tab_capacity_log_parameter_p20260407_call_time_idx;


--
-- Name: tab_capacity_log_parameter_p20260408_call_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_parameter_p_call_id ATTACH PARTITION public.tab_capacity_log_parameter_p20260408_call_id_idx;


--
-- Name: tab_capacity_log_parameter_p20260408_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_parameter_p_call_time ATTACH PARTITION public.tab_capacity_log_parameter_p20260408_call_time_idx;


--
-- Name: tab_capacity_log_parameter_p20260409_call_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_parameter_p_call_id ATTACH PARTITION public.tab_capacity_log_parameter_p20260409_call_id_idx;


--
-- Name: tab_capacity_log_parameter_p20260409_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_parameter_p_call_time ATTACH PARTITION public.tab_capacity_log_parameter_p20260409_call_time_idx;


--
-- Name: tab_capacity_log_parameter_p20260410_call_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_parameter_p_call_id ATTACH PARTITION public.tab_capacity_log_parameter_p20260410_call_id_idx;


--
-- Name: tab_capacity_log_parameter_p20260410_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_parameter_p_call_time ATTACH PARTITION public.tab_capacity_log_parameter_p20260410_call_time_idx;


--
-- Name: tab_capacity_log_parameter_p20260411_call_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_parameter_p_call_id ATTACH PARTITION public.tab_capacity_log_parameter_p20260411_call_id_idx;


--
-- Name: tab_capacity_log_parameter_p20260411_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_parameter_p_call_time ATTACH PARTITION public.tab_capacity_log_parameter_p20260411_call_time_idx;


--
-- Name: tab_capacity_log_parameter_p20260412_call_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_parameter_p_call_id ATTACH PARTITION public.tab_capacity_log_parameter_p20260412_call_id_idx;


--
-- Name: tab_capacity_log_parameter_p20260412_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_parameter_p_call_time ATTACH PARTITION public.tab_capacity_log_parameter_p20260412_call_time_idx;


--
-- Name: tab_capacity_log_parameter_p20260413_call_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_parameter_p_call_id ATTACH PARTITION public.tab_capacity_log_parameter_p20260413_call_id_idx;


--
-- Name: tab_capacity_log_parameter_p20260413_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_parameter_p_call_time ATTACH PARTITION public.tab_capacity_log_parameter_p20260413_call_time_idx;


--
-- Name: tab_capacity_log_parameter_p20260414_call_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_parameter_p_call_id ATTACH PARTITION public.tab_capacity_log_parameter_p20260414_call_id_idx;


--
-- Name: tab_capacity_log_parameter_p20260414_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_parameter_p_call_time ATTACH PARTITION public.tab_capacity_log_parameter_p20260414_call_time_idx;


--
-- Name: tab_capacity_log_parameter_p20260415_call_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_parameter_p_call_id ATTACH PARTITION public.tab_capacity_log_parameter_p20260415_call_id_idx;


--
-- Name: tab_capacity_log_parameter_p20260415_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_parameter_p_call_time ATTACH PARTITION public.tab_capacity_log_parameter_p20260415_call_time_idx;


--
-- Name: tab_capacity_log_parameter_p20260416_call_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_parameter_p_call_id ATTACH PARTITION public.tab_capacity_log_parameter_p20260416_call_id_idx;


--
-- Name: tab_capacity_log_parameter_p20260416_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_parameter_p_call_time ATTACH PARTITION public.tab_capacity_log_parameter_p20260416_call_time_idx;


--
-- Name: tab_capacity_log_parameter_p20260417_call_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_parameter_p_call_id ATTACH PARTITION public.tab_capacity_log_parameter_p20260417_call_id_idx;


--
-- Name: tab_capacity_log_parameter_p20260417_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_parameter_p_call_time ATTACH PARTITION public.tab_capacity_log_parameter_p20260417_call_time_idx;


--
-- Name: tab_capacity_log_parameter_p20260418_call_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_parameter_p_call_id ATTACH PARTITION public.tab_capacity_log_parameter_p20260418_call_id_idx;


--
-- Name: tab_capacity_log_parameter_p20260418_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_parameter_p_call_time ATTACH PARTITION public.tab_capacity_log_parameter_p20260418_call_time_idx;


--
-- Name: tab_capacity_log_parameter_p20260419_call_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_parameter_p_call_id ATTACH PARTITION public.tab_capacity_log_parameter_p20260419_call_id_idx;


--
-- Name: tab_capacity_log_parameter_p20260419_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_parameter_p_call_time ATTACH PARTITION public.tab_capacity_log_parameter_p20260419_call_time_idx;


--
-- Name: tab_capacity_log_parameter_p20260420_call_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_parameter_p_call_id ATTACH PARTITION public.tab_capacity_log_parameter_p20260420_call_id_idx;


--
-- Name: tab_capacity_log_parameter_p20260420_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_parameter_p_call_time ATTACH PARTITION public.tab_capacity_log_parameter_p20260420_call_time_idx;


--
-- Name: tab_capacity_log_parameter_p20260421_call_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_parameter_p_call_id ATTACH PARTITION public.tab_capacity_log_parameter_p20260421_call_id_idx;


--
-- Name: tab_capacity_log_parameter_p20260421_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_parameter_p_call_time ATTACH PARTITION public.tab_capacity_log_parameter_p20260421_call_time_idx;


--
-- Name: tab_capacity_log_parameter_p20260422_call_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_parameter_p_call_id ATTACH PARTITION public.tab_capacity_log_parameter_p20260422_call_id_idx;


--
-- Name: tab_capacity_log_parameter_p20260422_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_parameter_p_call_time ATTACH PARTITION public.tab_capacity_log_parameter_p20260422_call_time_idx;


--
-- Name: tab_capacity_log_parameter_p20260423_call_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_parameter_p_call_id ATTACH PARTITION public.tab_capacity_log_parameter_p20260423_call_id_idx;


--
-- Name: tab_capacity_log_parameter_p20260423_call_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_tab_capacity_log_parameter_p_call_time ATTACH PARTITION public.tab_capacity_log_parameter_p20260423_call_time_idx;


--
-- Name: tab_ux_inform_log_default_create_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_time ATTACH PARTITION public.tab_ux_inform_log_default_create_time_idx;


--
-- Name: tab_ux_inform_log_default_create_time_success_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_time_success ATTACH PARTITION public.tab_ux_inform_log_default_create_time_success_idx;


--
-- Name: tab_ux_inform_log_default_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_id ATTACH PARTITION public.tab_ux_inform_log_default_id_idx;


--
-- Name: tab_ux_inform_log_default_serial_number_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_sn ATTACH PARTITION public.tab_ux_inform_log_default_serial_number_idx;


--
-- Name: tab_ux_inform_log_p20260323_create_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_time ATTACH PARTITION public.tab_ux_inform_log_p20260323_create_time_idx;


--
-- Name: tab_ux_inform_log_p20260323_create_time_success_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_time_success ATTACH PARTITION public.tab_ux_inform_log_p20260323_create_time_success_idx;


--
-- Name: tab_ux_inform_log_p20260323_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_id ATTACH PARTITION public.tab_ux_inform_log_p20260323_id_idx;


--
-- Name: tab_ux_inform_log_p20260323_serial_number_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_sn ATTACH PARTITION public.tab_ux_inform_log_p20260323_serial_number_idx;


--
-- Name: tab_ux_inform_log_p20260324_create_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_time ATTACH PARTITION public.tab_ux_inform_log_p20260324_create_time_idx;


--
-- Name: tab_ux_inform_log_p20260324_create_time_success_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_time_success ATTACH PARTITION public.tab_ux_inform_log_p20260324_create_time_success_idx;


--
-- Name: tab_ux_inform_log_p20260324_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_id ATTACH PARTITION public.tab_ux_inform_log_p20260324_id_idx;


--
-- Name: tab_ux_inform_log_p20260324_serial_number_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_sn ATTACH PARTITION public.tab_ux_inform_log_p20260324_serial_number_idx;


--
-- Name: tab_ux_inform_log_p20260325_create_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_time ATTACH PARTITION public.tab_ux_inform_log_p20260325_create_time_idx;


--
-- Name: tab_ux_inform_log_p20260325_create_time_success_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_time_success ATTACH PARTITION public.tab_ux_inform_log_p20260325_create_time_success_idx;


--
-- Name: tab_ux_inform_log_p20260325_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_id ATTACH PARTITION public.tab_ux_inform_log_p20260325_id_idx;


--
-- Name: tab_ux_inform_log_p20260325_serial_number_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_sn ATTACH PARTITION public.tab_ux_inform_log_p20260325_serial_number_idx;


--
-- Name: tab_ux_inform_log_p20260326_create_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_time ATTACH PARTITION public.tab_ux_inform_log_p20260326_create_time_idx;


--
-- Name: tab_ux_inform_log_p20260326_create_time_success_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_time_success ATTACH PARTITION public.tab_ux_inform_log_p20260326_create_time_success_idx;


--
-- Name: tab_ux_inform_log_p20260326_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_id ATTACH PARTITION public.tab_ux_inform_log_p20260326_id_idx;


--
-- Name: tab_ux_inform_log_p20260326_serial_number_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_sn ATTACH PARTITION public.tab_ux_inform_log_p20260326_serial_number_idx;


--
-- Name: tab_ux_inform_log_p20260327_create_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_time ATTACH PARTITION public.tab_ux_inform_log_p20260327_create_time_idx;


--
-- Name: tab_ux_inform_log_p20260327_create_time_success_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_time_success ATTACH PARTITION public.tab_ux_inform_log_p20260327_create_time_success_idx;


--
-- Name: tab_ux_inform_log_p20260327_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_id ATTACH PARTITION public.tab_ux_inform_log_p20260327_id_idx;


--
-- Name: tab_ux_inform_log_p20260327_serial_number_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_sn ATTACH PARTITION public.tab_ux_inform_log_p20260327_serial_number_idx;


--
-- Name: tab_ux_inform_log_p20260328_create_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_time ATTACH PARTITION public.tab_ux_inform_log_p20260328_create_time_idx;


--
-- Name: tab_ux_inform_log_p20260328_create_time_success_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_time_success ATTACH PARTITION public.tab_ux_inform_log_p20260328_create_time_success_idx;


--
-- Name: tab_ux_inform_log_p20260328_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_id ATTACH PARTITION public.tab_ux_inform_log_p20260328_id_idx;


--
-- Name: tab_ux_inform_log_p20260328_serial_number_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_sn ATTACH PARTITION public.tab_ux_inform_log_p20260328_serial_number_idx;


--
-- Name: tab_ux_inform_log_p20260329_create_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_time ATTACH PARTITION public.tab_ux_inform_log_p20260329_create_time_idx;


--
-- Name: tab_ux_inform_log_p20260329_create_time_success_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_time_success ATTACH PARTITION public.tab_ux_inform_log_p20260329_create_time_success_idx;


--
-- Name: tab_ux_inform_log_p20260329_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_id ATTACH PARTITION public.tab_ux_inform_log_p20260329_id_idx;


--
-- Name: tab_ux_inform_log_p20260329_serial_number_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_sn ATTACH PARTITION public.tab_ux_inform_log_p20260329_serial_number_idx;


--
-- Name: tab_ux_inform_log_p20260330_create_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_time ATTACH PARTITION public.tab_ux_inform_log_p20260330_create_time_idx;


--
-- Name: tab_ux_inform_log_p20260330_create_time_success_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_time_success ATTACH PARTITION public.tab_ux_inform_log_p20260330_create_time_success_idx;


--
-- Name: tab_ux_inform_log_p20260330_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_id ATTACH PARTITION public.tab_ux_inform_log_p20260330_id_idx;


--
-- Name: tab_ux_inform_log_p20260330_serial_number_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_sn ATTACH PARTITION public.tab_ux_inform_log_p20260330_serial_number_idx;


--
-- Name: tab_ux_inform_log_p20260331_create_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_time ATTACH PARTITION public.tab_ux_inform_log_p20260331_create_time_idx;


--
-- Name: tab_ux_inform_log_p20260331_create_time_success_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_time_success ATTACH PARTITION public.tab_ux_inform_log_p20260331_create_time_success_idx;


--
-- Name: tab_ux_inform_log_p20260331_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_id ATTACH PARTITION public.tab_ux_inform_log_p20260331_id_idx;


--
-- Name: tab_ux_inform_log_p20260331_serial_number_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_sn ATTACH PARTITION public.tab_ux_inform_log_p20260331_serial_number_idx;


--
-- Name: tab_ux_inform_log_p20260401_create_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_time ATTACH PARTITION public.tab_ux_inform_log_p20260401_create_time_idx;


--
-- Name: tab_ux_inform_log_p20260401_create_time_success_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_time_success ATTACH PARTITION public.tab_ux_inform_log_p20260401_create_time_success_idx;


--
-- Name: tab_ux_inform_log_p20260401_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_id ATTACH PARTITION public.tab_ux_inform_log_p20260401_id_idx;


--
-- Name: tab_ux_inform_log_p20260401_serial_number_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_sn ATTACH PARTITION public.tab_ux_inform_log_p20260401_serial_number_idx;


--
-- Name: tab_ux_inform_log_p20260402_create_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_time ATTACH PARTITION public.tab_ux_inform_log_p20260402_create_time_idx;


--
-- Name: tab_ux_inform_log_p20260402_create_time_success_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_time_success ATTACH PARTITION public.tab_ux_inform_log_p20260402_create_time_success_idx;


--
-- Name: tab_ux_inform_log_p20260402_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_id ATTACH PARTITION public.tab_ux_inform_log_p20260402_id_idx;


--
-- Name: tab_ux_inform_log_p20260402_serial_number_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_sn ATTACH PARTITION public.tab_ux_inform_log_p20260402_serial_number_idx;


--
-- Name: tab_ux_inform_log_p20260403_create_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_time ATTACH PARTITION public.tab_ux_inform_log_p20260403_create_time_idx;


--
-- Name: tab_ux_inform_log_p20260403_create_time_success_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_time_success ATTACH PARTITION public.tab_ux_inform_log_p20260403_create_time_success_idx;


--
-- Name: tab_ux_inform_log_p20260403_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_id ATTACH PARTITION public.tab_ux_inform_log_p20260403_id_idx;


--
-- Name: tab_ux_inform_log_p20260403_serial_number_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_sn ATTACH PARTITION public.tab_ux_inform_log_p20260403_serial_number_idx;


--
-- Name: tab_ux_inform_log_p20260404_create_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_time ATTACH PARTITION public.tab_ux_inform_log_p20260404_create_time_idx;


--
-- Name: tab_ux_inform_log_p20260404_create_time_success_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_time_success ATTACH PARTITION public.tab_ux_inform_log_p20260404_create_time_success_idx;


--
-- Name: tab_ux_inform_log_p20260404_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_id ATTACH PARTITION public.tab_ux_inform_log_p20260404_id_idx;


--
-- Name: tab_ux_inform_log_p20260404_serial_number_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_sn ATTACH PARTITION public.tab_ux_inform_log_p20260404_serial_number_idx;


--
-- Name: tab_ux_inform_log_p20260405_create_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_time ATTACH PARTITION public.tab_ux_inform_log_p20260405_create_time_idx;


--
-- Name: tab_ux_inform_log_p20260405_create_time_success_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_time_success ATTACH PARTITION public.tab_ux_inform_log_p20260405_create_time_success_idx;


--
-- Name: tab_ux_inform_log_p20260405_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_id ATTACH PARTITION public.tab_ux_inform_log_p20260405_id_idx;


--
-- Name: tab_ux_inform_log_p20260405_serial_number_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_sn ATTACH PARTITION public.tab_ux_inform_log_p20260405_serial_number_idx;


--
-- Name: tab_ux_inform_log_p20260406_create_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_time ATTACH PARTITION public.tab_ux_inform_log_p20260406_create_time_idx;


--
-- Name: tab_ux_inform_log_p20260406_create_time_success_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_time_success ATTACH PARTITION public.tab_ux_inform_log_p20260406_create_time_success_idx;


--
-- Name: tab_ux_inform_log_p20260406_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_id ATTACH PARTITION public.tab_ux_inform_log_p20260406_id_idx;


--
-- Name: tab_ux_inform_log_p20260406_serial_number_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_sn ATTACH PARTITION public.tab_ux_inform_log_p20260406_serial_number_idx;


--
-- Name: tab_ux_inform_log_p20260407_create_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_time ATTACH PARTITION public.tab_ux_inform_log_p20260407_create_time_idx;


--
-- Name: tab_ux_inform_log_p20260407_create_time_success_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_time_success ATTACH PARTITION public.tab_ux_inform_log_p20260407_create_time_success_idx;


--
-- Name: tab_ux_inform_log_p20260407_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_id ATTACH PARTITION public.tab_ux_inform_log_p20260407_id_idx;


--
-- Name: tab_ux_inform_log_p20260407_serial_number_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_sn ATTACH PARTITION public.tab_ux_inform_log_p20260407_serial_number_idx;


--
-- Name: tab_ux_inform_log_p20260408_create_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_time ATTACH PARTITION public.tab_ux_inform_log_p20260408_create_time_idx;


--
-- Name: tab_ux_inform_log_p20260408_create_time_success_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_time_success ATTACH PARTITION public.tab_ux_inform_log_p20260408_create_time_success_idx;


--
-- Name: tab_ux_inform_log_p20260408_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_id ATTACH PARTITION public.tab_ux_inform_log_p20260408_id_idx;


--
-- Name: tab_ux_inform_log_p20260408_serial_number_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_sn ATTACH PARTITION public.tab_ux_inform_log_p20260408_serial_number_idx;


--
-- Name: tab_ux_inform_log_p20260409_create_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_time ATTACH PARTITION public.tab_ux_inform_log_p20260409_create_time_idx;


--
-- Name: tab_ux_inform_log_p20260409_create_time_success_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_time_success ATTACH PARTITION public.tab_ux_inform_log_p20260409_create_time_success_idx;


--
-- Name: tab_ux_inform_log_p20260409_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_id ATTACH PARTITION public.tab_ux_inform_log_p20260409_id_idx;


--
-- Name: tab_ux_inform_log_p20260409_serial_number_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_sn ATTACH PARTITION public.tab_ux_inform_log_p20260409_serial_number_idx;


--
-- Name: tab_ux_inform_log_p20260410_create_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_time ATTACH PARTITION public.tab_ux_inform_log_p20260410_create_time_idx;


--
-- Name: tab_ux_inform_log_p20260410_create_time_success_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_time_success ATTACH PARTITION public.tab_ux_inform_log_p20260410_create_time_success_idx;


--
-- Name: tab_ux_inform_log_p20260410_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_id ATTACH PARTITION public.tab_ux_inform_log_p20260410_id_idx;


--
-- Name: tab_ux_inform_log_p20260410_serial_number_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_sn ATTACH PARTITION public.tab_ux_inform_log_p20260410_serial_number_idx;


--
-- Name: tab_ux_inform_log_p20260411_create_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_time ATTACH PARTITION public.tab_ux_inform_log_p20260411_create_time_idx;


--
-- Name: tab_ux_inform_log_p20260411_create_time_success_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_time_success ATTACH PARTITION public.tab_ux_inform_log_p20260411_create_time_success_idx;


--
-- Name: tab_ux_inform_log_p20260411_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_id ATTACH PARTITION public.tab_ux_inform_log_p20260411_id_idx;


--
-- Name: tab_ux_inform_log_p20260411_serial_number_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_sn ATTACH PARTITION public.tab_ux_inform_log_p20260411_serial_number_idx;


--
-- Name: tab_ux_inform_log_p20260412_create_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_time ATTACH PARTITION public.tab_ux_inform_log_p20260412_create_time_idx;


--
-- Name: tab_ux_inform_log_p20260412_create_time_success_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_time_success ATTACH PARTITION public.tab_ux_inform_log_p20260412_create_time_success_idx;


--
-- Name: tab_ux_inform_log_p20260412_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_id ATTACH PARTITION public.tab_ux_inform_log_p20260412_id_idx;


--
-- Name: tab_ux_inform_log_p20260412_serial_number_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_sn ATTACH PARTITION public.tab_ux_inform_log_p20260412_serial_number_idx;


--
-- Name: tab_ux_inform_log_p20260413_create_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_time ATTACH PARTITION public.tab_ux_inform_log_p20260413_create_time_idx;


--
-- Name: tab_ux_inform_log_p20260413_create_time_success_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_time_success ATTACH PARTITION public.tab_ux_inform_log_p20260413_create_time_success_idx;


--
-- Name: tab_ux_inform_log_p20260413_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_id ATTACH PARTITION public.tab_ux_inform_log_p20260413_id_idx;


--
-- Name: tab_ux_inform_log_p20260413_serial_number_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_sn ATTACH PARTITION public.tab_ux_inform_log_p20260413_serial_number_idx;


--
-- Name: tab_ux_inform_log_p20260414_create_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_time ATTACH PARTITION public.tab_ux_inform_log_p20260414_create_time_idx;


--
-- Name: tab_ux_inform_log_p20260414_create_time_success_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_time_success ATTACH PARTITION public.tab_ux_inform_log_p20260414_create_time_success_idx;


--
-- Name: tab_ux_inform_log_p20260414_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_id ATTACH PARTITION public.tab_ux_inform_log_p20260414_id_idx;


--
-- Name: tab_ux_inform_log_p20260414_serial_number_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_sn ATTACH PARTITION public.tab_ux_inform_log_p20260414_serial_number_idx;


--
-- Name: tab_ux_inform_log_p20260415_create_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_time ATTACH PARTITION public.tab_ux_inform_log_p20260415_create_time_idx;


--
-- Name: tab_ux_inform_log_p20260415_create_time_success_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_time_success ATTACH PARTITION public.tab_ux_inform_log_p20260415_create_time_success_idx;


--
-- Name: tab_ux_inform_log_p20260415_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_id ATTACH PARTITION public.tab_ux_inform_log_p20260415_id_idx;


--
-- Name: tab_ux_inform_log_p20260415_serial_number_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_sn ATTACH PARTITION public.tab_ux_inform_log_p20260415_serial_number_idx;


--
-- Name: tab_ux_inform_log_p20260416_create_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_time ATTACH PARTITION public.tab_ux_inform_log_p20260416_create_time_idx;


--
-- Name: tab_ux_inform_log_p20260416_create_time_success_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_time_success ATTACH PARTITION public.tab_ux_inform_log_p20260416_create_time_success_idx;


--
-- Name: tab_ux_inform_log_p20260416_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_id ATTACH PARTITION public.tab_ux_inform_log_p20260416_id_idx;


--
-- Name: tab_ux_inform_log_p20260416_serial_number_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_sn ATTACH PARTITION public.tab_ux_inform_log_p20260416_serial_number_idx;


--
-- Name: tab_ux_inform_log_p20260417_create_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_time ATTACH PARTITION public.tab_ux_inform_log_p20260417_create_time_idx;


--
-- Name: tab_ux_inform_log_p20260417_create_time_success_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_time_success ATTACH PARTITION public.tab_ux_inform_log_p20260417_create_time_success_idx;


--
-- Name: tab_ux_inform_log_p20260417_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_id ATTACH PARTITION public.tab_ux_inform_log_p20260417_id_idx;


--
-- Name: tab_ux_inform_log_p20260417_serial_number_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_sn ATTACH PARTITION public.tab_ux_inform_log_p20260417_serial_number_idx;


--
-- Name: tab_ux_inform_log_p20260418_create_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_time ATTACH PARTITION public.tab_ux_inform_log_p20260418_create_time_idx;


--
-- Name: tab_ux_inform_log_p20260418_create_time_success_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_time_success ATTACH PARTITION public.tab_ux_inform_log_p20260418_create_time_success_idx;


--
-- Name: tab_ux_inform_log_p20260418_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_id ATTACH PARTITION public.tab_ux_inform_log_p20260418_id_idx;


--
-- Name: tab_ux_inform_log_p20260418_serial_number_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_sn ATTACH PARTITION public.tab_ux_inform_log_p20260418_serial_number_idx;


--
-- Name: tab_ux_inform_log_p20260419_create_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_time ATTACH PARTITION public.tab_ux_inform_log_p20260419_create_time_idx;


--
-- Name: tab_ux_inform_log_p20260419_create_time_success_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_time_success ATTACH PARTITION public.tab_ux_inform_log_p20260419_create_time_success_idx;


--
-- Name: tab_ux_inform_log_p20260419_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_id ATTACH PARTITION public.tab_ux_inform_log_p20260419_id_idx;


--
-- Name: tab_ux_inform_log_p20260419_serial_number_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_sn ATTACH PARTITION public.tab_ux_inform_log_p20260419_serial_number_idx;


--
-- Name: tab_ux_inform_log_p20260420_create_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_time ATTACH PARTITION public.tab_ux_inform_log_p20260420_create_time_idx;


--
-- Name: tab_ux_inform_log_p20260420_create_time_success_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_time_success ATTACH PARTITION public.tab_ux_inform_log_p20260420_create_time_success_idx;


--
-- Name: tab_ux_inform_log_p20260420_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_id ATTACH PARTITION public.tab_ux_inform_log_p20260420_id_idx;


--
-- Name: tab_ux_inform_log_p20260420_serial_number_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_sn ATTACH PARTITION public.tab_ux_inform_log_p20260420_serial_number_idx;


--
-- Name: tab_ux_inform_log_p20260421_create_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_time ATTACH PARTITION public.tab_ux_inform_log_p20260421_create_time_idx;


--
-- Name: tab_ux_inform_log_p20260421_create_time_success_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_time_success ATTACH PARTITION public.tab_ux_inform_log_p20260421_create_time_success_idx;


--
-- Name: tab_ux_inform_log_p20260421_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_id ATTACH PARTITION public.tab_ux_inform_log_p20260421_id_idx;


--
-- Name: tab_ux_inform_log_p20260421_serial_number_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_sn ATTACH PARTITION public.tab_ux_inform_log_p20260421_serial_number_idx;


--
-- Name: tab_ux_inform_log_p20260422_create_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_time ATTACH PARTITION public.tab_ux_inform_log_p20260422_create_time_idx;


--
-- Name: tab_ux_inform_log_p20260422_create_time_success_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_time_success ATTACH PARTITION public.tab_ux_inform_log_p20260422_create_time_success_idx;


--
-- Name: tab_ux_inform_log_p20260422_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_id ATTACH PARTITION public.tab_ux_inform_log_p20260422_id_idx;


--
-- Name: tab_ux_inform_log_p20260422_serial_number_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_sn ATTACH PARTITION public.tab_ux_inform_log_p20260422_serial_number_idx;


--
-- Name: tab_ux_inform_log_p20260423_create_time_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_time ATTACH PARTITION public.tab_ux_inform_log_p20260423_create_time_idx;


--
-- Name: tab_ux_inform_log_p20260423_create_time_success_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_time_success ATTACH PARTITION public.tab_ux_inform_log_p20260423_create_time_success_idx;


--
-- Name: tab_ux_inform_log_p20260423_id_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_id ATTACH PARTITION public.tab_ux_inform_log_p20260423_id_idx;


--
-- Name: tab_ux_inform_log_p20260423_serial_number_idx; Type: INDEX ATTACH; Schema: public; Owner: gtmsmanager
--

ALTER INDEX public.idx_ux_inform_log_p_sn ATTACH PARTITION public.tab_ux_inform_log_p20260423_serial_number_idx;


--
-- Name: dbz_publication; Type: PUBLICATION; Schema: -; Owner: gtmsmanager
--

CREATE PUBLICATION dbz_publication FOR ALL TABLES WITH (publish = 'insert, update, delete, truncate');


ALTER PUBLICATION dbz_publication OWNER TO gtmsmanager;

--
-- Name: TABLE bind_log; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.bind_log TO exporter;


--
-- Name: TABLE bind_type; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.bind_type TO exporter;


--
-- Name: TABLE bridge_route_oper_log; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.bridge_route_oper_log TO exporter;


--
-- Name: TABLE cpe_gather_config; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.cpe_gather_config TO exporter;


--
-- Name: TABLE cpe_gather_node_tabname; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.cpe_gather_node_tabname TO exporter;


--
-- Name: TABLE cpe_gather_param_type; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.cpe_gather_param_type TO exporter;


--
-- Name: TABLE cpe_gather_param_type_bbms; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.cpe_gather_param_type_bbms TO exporter;


--
-- Name: TABLE cpe_gather_record; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.cpe_gather_record TO exporter;


--
-- Name: TABLE cpe_gather_result; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.cpe_gather_result TO exporter;


--
-- Name: TABLE dev_event_type; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.dev_event_type TO exporter;


--
-- Name: TABLE egw_item_role; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.egw_item_role TO exporter;


--
-- Name: TABLE egwcust_serv_info; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.egwcust_serv_info TO exporter;


--
-- Name: TABLE en_sys_permission; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.en_sys_permission TO exporter;


--
-- Name: TABLE guangkuan_reboot_info; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.guangkuan_reboot_info TO exporter;


--
-- Name: TABLE gw_access_type; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_access_type TO exporter;


--
-- Name: TABLE gw_acs_stream; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_acs_stream TO exporter;


--
-- Name: TABLE gw_acs_stream_content; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_acs_stream_content TO exporter;


--
-- Name: TABLE gw_alg; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_alg TO exporter;


--
-- Name: TABLE gw_alg_bbms; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_alg_bbms TO exporter;


--
-- Name: TABLE gw_card_manage; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_card_manage TO exporter;


--
-- Name: TABLE gw_conf_template; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_conf_template TO exporter;


--
-- Name: TABLE gw_conf_template_service; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_conf_template_service TO exporter;


--
-- Name: TABLE gw_cust_user_dev_type; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_cust_user_dev_type TO exporter;


--
-- Name: TABLE gw_cust_user_package; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_cust_user_package TO exporter;


--
-- Name: TABLE gw_cust_user_package_copy1; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_cust_user_package_copy1 TO exporter;


--
-- Name: TABLE gw_dev_model_dev_type; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_dev_model_dev_type TO exporter;


--
-- Name: TABLE gw_dev_serv; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_dev_serv TO exporter;


--
-- Name: TABLE gw_dev_type; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_dev_type TO exporter;


--
-- Name: TABLE gw_device_model; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_device_model TO exporter;


--
-- Name: TABLE gw_device_restart_batch; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_device_restart_batch TO exporter;


--
-- Name: TABLE gw_device_restart_task; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_device_restart_task TO exporter;


--
-- Name: TABLE gw_devicestatus; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_devicestatus TO exporter;


--
-- Name: TABLE gw_devicestatus_history; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_devicestatus_history TO exporter;


--
-- Name: TABLE gw_egw_expert; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_egw_expert TO exporter;


--
-- Name: TABLE gw_exception; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_exception TO exporter;


--
-- Name: TABLE gw_fire_wall; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_fire_wall TO exporter;


--
-- Name: TABLE gw_ipmain; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_ipmain TO exporter;


--
-- Name: TABLE gw_iptv; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_iptv TO exporter;


--
-- Name: TABLE gw_iptv_bbms; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_iptv_bbms TO exporter;


--
-- Name: TABLE gw_lan_eth; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_lan_eth TO exporter;


--
-- Name: TABLE gw_lan_eth_history; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_lan_eth_history TO exporter;


--
-- Name: TABLE gw_lan_eth_namechange; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_lan_eth_namechange TO exporter;


--
-- Name: TABLE gw_lan_host; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_lan_host TO exporter;


--
-- Name: TABLE gw_lan_host_bbms; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_lan_host_bbms TO exporter;


--
-- Name: TABLE gw_lan_host_history; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_lan_host_history TO exporter;


--
-- Name: TABLE gw_lan_hostconf; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_lan_hostconf TO exporter;


--
-- Name: TABLE gw_lan_hostconf_bbms; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_lan_hostconf_bbms TO exporter;


--
-- Name: TABLE gw_lan_hostconf_history; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_lan_hostconf_history TO exporter;


--
-- Name: TABLE gw_lan_vlan_dhcp; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_lan_vlan_dhcp TO exporter;


--
-- Name: TABLE gw_lan_vlan_num; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_lan_vlan_num TO exporter;


--
-- Name: TABLE gw_lan_wlan; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_lan_wlan TO exporter;


--
-- Name: TABLE gw_lan_wlan_bbms; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_lan_wlan_bbms TO exporter;


--
-- Name: TABLE gw_lan_wlan_health; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_lan_wlan_health TO exporter;


--
-- Name: TABLE gw_lan_wlan_history; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_lan_wlan_history TO exporter;


--
-- Name: TABLE gw_lan_wlan_namechange; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_lan_wlan_namechange TO exporter;


--
-- Name: TABLE gw_monitor_task; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_monitor_task TO exporter;


--
-- Name: TABLE gw_mwband; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_mwband TO exporter;


--
-- Name: TABLE gw_mwband_bbms; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_mwband_bbms TO exporter;


--
-- Name: TABLE gw_office_voip; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_office_voip TO exporter;


--
-- Name: TABLE gw_online_config; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_online_config TO exporter;


--
-- Name: TABLE gw_online_report; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_online_report TO exporter;


--
-- Name: TABLE gw_order_type; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_order_type TO exporter;


--
-- Name: TABLE gw_ping; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_ping TO exporter;


--
-- Name: TABLE gw_qos; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_qos TO exporter;


--
-- Name: TABLE gw_qos_app; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_qos_app TO exporter;


--
-- Name: TABLE gw_qos_app_bbms; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_qos_app_bbms TO exporter;


--
-- Name: TABLE gw_qos_bbms; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_qos_bbms TO exporter;


--
-- Name: TABLE gw_qos_class; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_qos_class TO exporter;


--
-- Name: TABLE gw_qos_class_bbms; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_qos_class_bbms TO exporter;


--
-- Name: TABLE gw_qos_class_type; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_qos_class_type TO exporter;


--
-- Name: TABLE gw_qos_class_type_bbms; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_qos_class_type_bbms TO exporter;


--
-- Name: TABLE gw_qos_queue; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_qos_queue TO exporter;


--
-- Name: TABLE gw_qos_queue_bbms; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_qos_queue_bbms TO exporter;


--
-- Name: TABLE gw_sec_access_control_bbms; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_sec_access_control_bbms TO exporter;


--
-- Name: TABLE gw_sec_antivirus_bbms; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_sec_antivirus_bbms TO exporter;


--
-- Name: TABLE gw_sec_content_filter_bbms; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_sec_content_filter_bbms TO exporter;


--
-- Name: TABLE gw_sec_intrusion_detect_bbms; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_sec_intrusion_detect_bbms TO exporter;


--
-- Name: TABLE gw_sec_mail_filter_bbms; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_sec_mail_filter_bbms TO exporter;


--
-- Name: TABLE gw_serv_beforehand; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_serv_beforehand TO exporter;


--
-- Name: TABLE gw_serv_default; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_serv_default TO exporter;


--
-- Name: TABLE gw_serv_default_value; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_serv_default_value TO exporter;


--
-- Name: TABLE gw_serv_package; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_serv_package TO exporter;


--
-- Name: TABLE gw_serv_package_type; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_serv_package_type TO exporter;


--
-- Name: TABLE gw_serv_setloid; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_serv_setloid TO exporter;


--
-- Name: TABLE gw_serv_strategy; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_serv_strategy TO exporter;


--
-- Name: TABLE gw_serv_strategy_batch; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_serv_strategy_batch TO exporter;


--
-- Name: TABLE gw_serv_strategy_log; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_serv_strategy_log TO exporter;


--
-- Name: TABLE gw_serv_strategy_serv; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_serv_strategy_serv TO exporter;


--
-- Name: TABLE gw_serv_strategy_serv_log; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_serv_strategy_serv_log TO exporter;


--
-- Name: TABLE gw_serv_strategy_soft; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_serv_strategy_soft TO exporter;


--
-- Name: TABLE gw_serv_strategy_soft_log; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_serv_strategy_soft_log TO exporter;


--
-- Name: TABLE gw_serv_type_device_type; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_serv_type_device_type TO exporter;


--
-- Name: TABLE gw_setloid_device; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_setloid_device TO exporter;


--
-- Name: TABLE gw_soft_record; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_soft_record TO exporter;


--
-- Name: TABLE gw_soft_upgrade_temp; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_soft_upgrade_temp TO exporter;


--
-- Name: TABLE gw_soft_upgrade_temp_map; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_soft_upgrade_temp_map TO exporter;


--
-- Name: TABLE gw_soft_upgrade_temp_map_log; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_soft_upgrade_temp_map_log TO exporter;


--
-- Name: TABLE gw_strategy_qos; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_strategy_qos TO exporter;


--
-- Name: TABLE gw_strategy_qos_param; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_strategy_qos_param TO exporter;


--
-- Name: TABLE gw_strategy_qos_tmpl; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_strategy_qos_tmpl TO exporter;


--
-- Name: TABLE gw_strategy_sheet; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_strategy_sheet TO exporter;


--
-- Name: TABLE gw_strategy_type; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_strategy_type TO exporter;


--
-- Name: TABLE gw_subnets; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_subnets TO exporter;


--
-- Name: TABLE gw_syslog_file; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_syslog_file TO exporter;


--
-- Name: TABLE gw_tr069; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_tr069 TO exporter;


--
-- Name: TABLE gw_tr069_bbms; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_tr069_bbms TO exporter;


--
-- Name: TABLE gw_traceroute; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_traceroute TO exporter;


--
-- Name: TABLE gw_user_midware_serv; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_user_midware_serv TO exporter;


--
-- Name: TABLE gw_usertype_servtype; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_usertype_servtype TO exporter;


--
-- Name: TABLE gw_version_file_path; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_version_file_path TO exporter;


--
-- Name: TABLE gw_voip; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_voip TO exporter;


--
-- Name: TABLE gw_voip_bbms; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_voip_bbms TO exporter;


--
-- Name: TABLE gw_voip_digit_device; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_voip_digit_device TO exporter;


--
-- Name: TABLE gw_voip_digit_map; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_voip_digit_map TO exporter;


--
-- Name: TABLE gw_voip_digit_task; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_voip_digit_task TO exporter;


--
-- Name: TABLE gw_voip_init_param; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_voip_init_param TO exporter;


--
-- Name: TABLE gw_voip_prof; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_voip_prof TO exporter;


--
-- Name: TABLE gw_voip_prof_bbms; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_voip_prof_bbms TO exporter;


--
-- Name: TABLE gw_voip_prof_h248; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_voip_prof_h248 TO exporter;


--
-- Name: TABLE gw_voip_prof_h248_bbms; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_voip_prof_h248_bbms TO exporter;


--
-- Name: TABLE gw_voip_prof_line; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_voip_prof_line TO exporter;


--
-- Name: TABLE gw_voip_prof_line_bbms; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_voip_prof_line_bbms TO exporter;


--
-- Name: TABLE gw_wan; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_wan TO exporter;


--
-- Name: TABLE gw_wan_bbms; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_wan_bbms TO exporter;


--
-- Name: TABLE gw_wan_conn; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_wan_conn TO exporter;


--
-- Name: TABLE gw_wan_conn_bbms; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_wan_conn_bbms TO exporter;


--
-- Name: TABLE gw_wan_conn_history; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_wan_conn_history TO exporter;


--
-- Name: TABLE gw_wan_conn_namechange; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_wan_conn_namechange TO exporter;


--
-- Name: TABLE gw_wan_conn_session; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_wan_conn_session TO exporter;


--
-- Name: TABLE gw_wan_conn_session_bbms; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_wan_conn_session_bbms TO exporter;


--
-- Name: TABLE gw_wan_conn_session_history; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_wan_conn_session_history TO exporter;


--
-- Name: TABLE gw_wan_conn_session_namechange; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_wan_conn_session_namechange TO exporter;


--
-- Name: TABLE gw_wan_conn_session_vpn_bbms; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_wan_conn_session_vpn_bbms TO exporter;


--
-- Name: TABLE gw_wan_dsl_inter_conf_health; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_wan_dsl_inter_conf_health TO exporter;


--
-- Name: TABLE gw_wan_history; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_wan_history TO exporter;


--
-- Name: TABLE gw_wan_namechange; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_wan_namechange TO exporter;


--
-- Name: TABLE gw_wan_wireinfo; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_wan_wireinfo TO exporter;


--
-- Name: TABLE gw_wan_wireinfo_bbms; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_wan_wireinfo_bbms TO exporter;


--
-- Name: TABLE gw_wan_wireinfo_epon; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_wan_wireinfo_epon TO exporter;


--
-- Name: TABLE gw_wan_wireinfo_epon_bbms; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_wan_wireinfo_epon_bbms TO exporter;


--
-- Name: TABLE gw_wan_wireinfo_epon_history; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_wan_wireinfo_epon_history TO exporter;


--
-- Name: TABLE gw_wan_wireinfo_history; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_wan_wireinfo_history TO exporter;


--
-- Name: TABLE gw_wlan_asso; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_wlan_asso TO exporter;


--
-- Name: TABLE gw_wlan_asso_bbms; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.gw_wlan_asso_bbms TO exporter;


--
-- Name: TABLE hgw_item_role; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.hgw_item_role TO exporter;


--
-- Name: TABLE hgwcust_serv_info; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.hgwcust_serv_info TO exporter;


--
-- Name: TABLE itms_bssuser_info; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.itms_bssuser_info TO exporter;


--
-- Name: TABLE itv_bss_dev_type; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.itv_bss_dev_type TO exporter;


--
-- Name: TABLE itv_customer_info; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.itv_customer_info TO exporter;


--
-- Name: TABLE itv_prod_spec; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.itv_prod_spec TO exporter;


--
-- Name: TABLE itv_serv_package; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.itv_serv_package TO exporter;


--
-- Name: TABLE log_gtms_service; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.log_gtms_service TO exporter;


--
-- Name: TABLE oss_file; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.oss_file TO exporter;


--
-- Name: TABLE poor_quality_device_restart; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.poor_quality_device_restart TO exporter;


--
-- Name: TABLE pp_itfs_data; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.pp_itfs_data TO exporter;


--
-- Name: TABLE sgw_model_security_template; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.sgw_model_security_template TO exporter;


--
-- Name: TABLE sgw_security; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.sgw_security TO exporter;


--
-- Name: TABLE stb_gw_device_model; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.stb_gw_device_model TO exporter;


--
-- Name: TABLE stb_gw_devicestatus; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.stb_gw_devicestatus TO exporter;


--
-- Name: TABLE stb_gw_filepath_devtype; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.stb_gw_filepath_devtype TO exporter;


--
-- Name: TABLE stb_gw_serv_strategy; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.stb_gw_serv_strategy TO exporter;


--
-- Name: TABLE stb_gw_serv_strategy_batch; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.stb_gw_serv_strategy_batch TO exporter;


--
-- Name: TABLE stb_gw_serv_strategy_batch_log; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.stb_gw_serv_strategy_batch_log TO exporter;


--
-- Name: TABLE stb_gw_serv_strategy_log; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.stb_gw_serv_strategy_log TO exporter;


--
-- Name: TABLE stb_gw_soft_upgrade_temp_map; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.stb_gw_soft_upgrade_temp_map TO exporter;


--
-- Name: TABLE stb_tab_boot_event; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.stb_tab_boot_event TO exporter;


--
-- Name: TABLE stb_tab_boot_event_tmp; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.stb_tab_boot_event_tmp TO exporter;


--
-- Name: TABLE stb_tab_customer; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.stb_tab_customer TO exporter;


--
-- Name: TABLE stb_tab_device_addressinfo; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.stb_tab_device_addressinfo TO exporter;


--
-- Name: TABLE stb_tab_devicetype_info; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.stb_tab_devicetype_info TO exporter;


--
-- Name: TABLE stb_tab_gw_device; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.stb_tab_gw_device TO exporter;


--
-- Name: TABLE stb_tab_gw_device_init_oui; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.stb_tab_gw_device_init_oui TO exporter;


--
-- Name: TABLE stb_tab_seniorquery_tmp; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.stb_tab_seniorquery_tmp TO exporter;


--
-- Name: TABLE stb_tab_setparamvalue_tmp; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.stb_tab_setparamvalue_tmp TO exporter;


--
-- Name: TABLE stb_tab_vendor; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.stb_tab_vendor TO exporter;


--
-- Name: TABLE stb_tab_vendor_oui; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.stb_tab_vendor_oui TO exporter;


--
-- Name: TABLE stb_task_batch_restart; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.stb_task_batch_restart TO exporter;


--
-- Name: TABLE sys_announcement; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.sys_announcement TO exporter;


--
-- Name: TABLE sys_announcement_send; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.sys_announcement_send TO exporter;


--
-- Name: TABLE sys_category; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.sys_category TO exporter;


--
-- Name: TABLE sys_check_rule; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.sys_check_rule TO exporter;


--
-- Name: TABLE sys_data_source; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.sys_data_source TO exporter;


--
-- Name: TABLE sys_depart; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.sys_depart TO exporter;


--
-- Name: TABLE sys_depart_permission; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.sys_depart_permission TO exporter;


--
-- Name: TABLE sys_depart_role; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.sys_depart_role TO exporter;


--
-- Name: TABLE sys_depart_role_permission; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.sys_depart_role_permission TO exporter;


--
-- Name: TABLE sys_depart_role_user; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.sys_depart_role_user TO exporter;


--
-- Name: TABLE sys_dict; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.sys_dict TO exporter;


--
-- Name: TABLE sys_dict_item; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.sys_dict_item TO exporter;


--
-- Name: TABLE sys_fill_rule; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.sys_fill_rule TO exporter;


--
-- Name: TABLE sys_gateway_route; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.sys_gateway_route TO exporter;


--
-- Name: TABLE sys_language_config; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.sys_language_config TO exporter;


--
-- Name: TABLE sys_log; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.sys_log TO exporter;


--
-- Name: TABLE sys_permission; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.sys_permission TO exporter;


--
-- Name: TABLE sys_permission_backup; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.sys_permission_backup TO exporter;


--
-- Name: TABLE sys_permission_bak0925; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.sys_permission_bak0925 TO exporter;


--
-- Name: TABLE sys_permission_data_rule; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.sys_permission_data_rule TO exporter;


--
-- Name: TABLE sys_position; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.sys_position TO exporter;


--
-- Name: TABLE sys_quartz_job; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.sys_quartz_job TO exporter;


--
-- Name: TABLE sys_role; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.sys_role TO exporter;


--
-- Name: TABLE sys_role_permission; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.sys_role_permission TO exporter;


--
-- Name: TABLE sys_sms_template; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.sys_sms_template TO exporter;


--
-- Name: TABLE sys_tenant; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.sys_tenant TO exporter;


--
-- Name: TABLE sys_user; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.sys_user TO exporter;


--
-- Name: TABLE sys_user_depart; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.sys_user_depart TO exporter;


--
-- Name: TABLE sys_user_password_history; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.sys_user_password_history TO exporter;


--
-- Name: TABLE sys_user_role; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.sys_user_role TO exporter;


--
-- Name: TABLE tab_acc_area; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_acc_area TO exporter;


--
-- Name: TABLE tab_alarm_record; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_alarm_record TO exporter;


--
-- Name: TABLE tab_app_sign_config; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_app_sign_config TO exporter;


--
-- Name: TABLE tab_area; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_area TO exporter;


--
-- Name: TABLE tab_attach_devlist; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_attach_devlist TO exporter;


--
-- Name: TABLE tab_auth; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_auth TO exporter;


--
-- Name: TABLE tab_batch_task_dev; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_batch_task_dev TO exporter;


--
-- Name: TABLE tab_batch_task_info; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_batch_task_info TO exporter;


--
-- Name: TABLE tab_batchgather_node; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_batchgather_node TO exporter;


--
-- Name: TABLE tab_batchgettemplate_task; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_batchgettemplate_task TO exporter;


--
-- Name: TABLE tab_batchhttp_task; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_batchhttp_task TO exporter;


--
-- Name: TABLE tab_batchhttp_task_dev; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_batchhttp_task_dev TO exporter;


--
-- Name: TABLE tab_batchrestart_period; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_batchrestart_period TO exporter;


--
-- Name: TABLE tab_batchsettemplate_dev; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_batchsettemplate_dev TO exporter;


--
-- Name: TABLE tab_batchsettemplate_task; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_batchsettemplate_task TO exporter;


--
-- Name: TABLE tab_batchspeed_result_temp; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_batchspeed_result_temp TO exporter;


--
-- Name: TABLE tab_batchspeedcheck_temp; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_batchspeedcheck_temp TO exporter;


--
-- Name: TABLE tab_bind_fail; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_bind_fail TO exporter;


--
-- Name: TABLE tab_black_ip; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_black_ip TO exporter;


--
-- Name: TABLE tab_blacklist_task; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_blacklist_task TO exporter;


--
-- Name: TABLE tab_boot_event; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_boot_event TO exporter;


--
-- Name: TABLE tab_broad_band_param; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_broad_band_param TO exporter;


--
-- Name: TABLE tab_broad_band_router; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_broad_band_router TO exporter;


--
-- Name: TABLE tab_bss_dev_port; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_bss_dev_port TO exporter;


--
-- Name: TABLE tab_bss_sheet; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_bss_sheet TO exporter;


--
-- Name: TABLE tab_bss_sheet_bak; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_bss_sheet_bak TO exporter;


--
-- Name: TABLE tab_capacity_log; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_capacity_log TO exporter;


--
-- Name: TABLE tab_capacity_log_bak_20260324121914; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_capacity_log_bak_20260324121914 TO exporter;


--
-- Name: TABLE tab_capacity_log_default; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_capacity_log_default TO exporter;


--
-- Name: TABLE tab_capacity_log_p20260323; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_capacity_log_p20260323 TO exporter;


--
-- Name: TABLE tab_capacity_log_p20260324; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_capacity_log_p20260324 TO exporter;


--
-- Name: TABLE tab_capacity_log_p20260325; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_capacity_log_p20260325 TO exporter;


--
-- Name: TABLE tab_capacity_log_p20260326; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_capacity_log_p20260326 TO exporter;


--
-- Name: TABLE tab_capacity_log_p20260327; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_capacity_log_p20260327 TO exporter;


--
-- Name: TABLE tab_capacity_log_p20260328; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_capacity_log_p20260328 TO exporter;


--
-- Name: TABLE tab_capacity_log_p20260329; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_capacity_log_p20260329 TO exporter;


--
-- Name: TABLE tab_capacity_log_p20260330; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_capacity_log_p20260330 TO exporter;


--
-- Name: TABLE tab_capacity_log_p20260331; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_capacity_log_p20260331 TO exporter;


--
-- Name: TABLE tab_capacity_log_p20260401; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_capacity_log_p20260401 TO exporter;


--
-- Name: TABLE tab_capacity_log_p20260402; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_capacity_log_p20260402 TO exporter;


--
-- Name: TABLE tab_capacity_log_p20260403; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_capacity_log_p20260403 TO exporter;


--
-- Name: TABLE tab_capacity_log_p20260404; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_capacity_log_p20260404 TO exporter;


--
-- Name: TABLE tab_capacity_log_p20260405; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_capacity_log_p20260405 TO exporter;


--
-- Name: TABLE tab_capacity_log_p20260406; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_capacity_log_p20260406 TO exporter;


--
-- Name: TABLE tab_capacity_log_p20260407; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_capacity_log_p20260407 TO exporter;


--
-- Name: TABLE tab_capacity_log_p20260408; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_capacity_log_p20260408 TO exporter;


--
-- Name: TABLE tab_capacity_log_p20260409; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_capacity_log_p20260409 TO exporter;


--
-- Name: TABLE tab_capacity_log_p20260410; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_capacity_log_p20260410 TO exporter;


--
-- Name: TABLE tab_capacity_log_p20260411; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_capacity_log_p20260411 TO exporter;


--
-- Name: TABLE tab_capacity_log_p20260412; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_capacity_log_p20260412 TO exporter;


--
-- Name: TABLE tab_capacity_log_p20260413; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_capacity_log_p20260413 TO exporter;


--
-- Name: TABLE tab_capacity_log_p20260414; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_capacity_log_p20260414 TO exporter;


--
-- Name: TABLE tab_capacity_log_p20260415; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_capacity_log_p20260415 TO exporter;


--
-- Name: TABLE tab_capacity_log_p20260416; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_capacity_log_p20260416 TO exporter;


--
-- Name: TABLE tab_capacity_log_p20260417; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_capacity_log_p20260417 TO exporter;


--
-- Name: TABLE tab_capacity_log_p20260418; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_capacity_log_p20260418 TO exporter;


--
-- Name: TABLE tab_capacity_log_p20260419; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_capacity_log_p20260419 TO exporter;


--
-- Name: TABLE tab_capacity_log_p20260420; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_capacity_log_p20260420 TO exporter;


--
-- Name: TABLE tab_capacity_log_p20260421; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_capacity_log_p20260421 TO exporter;


--
-- Name: TABLE tab_capacity_log_p20260422; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_capacity_log_p20260422 TO exporter;


--
-- Name: TABLE tab_capacity_log_p20260423; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_capacity_log_p20260423 TO exporter;


--
-- Name: TABLE tab_capacity_log_parameter; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_capacity_log_parameter TO exporter;


--
-- Name: TABLE tab_capacity_log_parameter_bak_20260324121914; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_capacity_log_parameter_bak_20260324121914 TO exporter;


--
-- Name: TABLE tab_capacity_log_parameter_default; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_capacity_log_parameter_default TO exporter;


--
-- Name: TABLE tab_capacity_log_parameter_p20260323; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_capacity_log_parameter_p20260323 TO exporter;


--
-- Name: TABLE tab_capacity_log_parameter_p20260324; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_capacity_log_parameter_p20260324 TO exporter;


--
-- Name: TABLE tab_capacity_log_parameter_p20260325; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_capacity_log_parameter_p20260325 TO exporter;


--
-- Name: TABLE tab_capacity_log_parameter_p20260326; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_capacity_log_parameter_p20260326 TO exporter;


--
-- Name: TABLE tab_capacity_log_parameter_p20260327; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_capacity_log_parameter_p20260327 TO exporter;


--
-- Name: TABLE tab_capacity_log_parameter_p20260328; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_capacity_log_parameter_p20260328 TO exporter;


--
-- Name: TABLE tab_capacity_log_parameter_p20260329; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_capacity_log_parameter_p20260329 TO exporter;


--
-- Name: TABLE tab_capacity_log_parameter_p20260330; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_capacity_log_parameter_p20260330 TO exporter;


--
-- Name: TABLE tab_capacity_log_parameter_p20260331; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_capacity_log_parameter_p20260331 TO exporter;


--
-- Name: TABLE tab_capacity_log_parameter_p20260401; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_capacity_log_parameter_p20260401 TO exporter;


--
-- Name: TABLE tab_capacity_log_parameter_p20260402; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_capacity_log_parameter_p20260402 TO exporter;


--
-- Name: TABLE tab_capacity_log_parameter_p20260403; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_capacity_log_parameter_p20260403 TO exporter;


--
-- Name: TABLE tab_capacity_log_parameter_p20260404; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_capacity_log_parameter_p20260404 TO exporter;


--
-- Name: TABLE tab_capacity_log_parameter_p20260405; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_capacity_log_parameter_p20260405 TO exporter;


--
-- Name: TABLE tab_capacity_log_parameter_p20260406; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_capacity_log_parameter_p20260406 TO exporter;


--
-- Name: TABLE tab_capacity_log_parameter_p20260407; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_capacity_log_parameter_p20260407 TO exporter;


--
-- Name: TABLE tab_capacity_log_parameter_p20260408; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_capacity_log_parameter_p20260408 TO exporter;


--
-- Name: TABLE tab_capacity_log_parameter_p20260409; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_capacity_log_parameter_p20260409 TO exporter;


--
-- Name: TABLE tab_capacity_log_parameter_p20260410; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_capacity_log_parameter_p20260410 TO exporter;


--
-- Name: TABLE tab_capacity_log_parameter_p20260411; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_capacity_log_parameter_p20260411 TO exporter;


--
-- Name: TABLE tab_capacity_log_parameter_p20260412; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_capacity_log_parameter_p20260412 TO exporter;


--
-- Name: TABLE tab_capacity_log_parameter_p20260413; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_capacity_log_parameter_p20260413 TO exporter;


--
-- Name: TABLE tab_capacity_log_parameter_p20260414; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_capacity_log_parameter_p20260414 TO exporter;


--
-- Name: TABLE tab_capacity_log_parameter_p20260415; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_capacity_log_parameter_p20260415 TO exporter;


--
-- Name: TABLE tab_capacity_log_parameter_p20260416; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_capacity_log_parameter_p20260416 TO exporter;


--
-- Name: TABLE tab_capacity_log_parameter_p20260417; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_capacity_log_parameter_p20260417 TO exporter;


--
-- Name: TABLE tab_capacity_log_parameter_p20260418; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_capacity_log_parameter_p20260418 TO exporter;


--
-- Name: TABLE tab_capacity_log_parameter_p20260419; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_capacity_log_parameter_p20260419 TO exporter;


--
-- Name: TABLE tab_capacity_log_parameter_p20260420; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_capacity_log_parameter_p20260420 TO exporter;


--
-- Name: TABLE tab_capacity_log_parameter_p20260421; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_capacity_log_parameter_p20260421 TO exporter;


--
-- Name: TABLE tab_capacity_log_parameter_p20260422; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_capacity_log_parameter_p20260422 TO exporter;


--
-- Name: TABLE tab_capacity_log_parameter_p20260423; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_capacity_log_parameter_p20260423 TO exporter;


--
-- Name: TABLE tab_capacity_log_parameter_zss; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_capacity_log_parameter_zss TO exporter;


--
-- Name: TABLE tab_capacity_log_zss; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_capacity_log_zss TO exporter;


--
-- Name: TABLE tab_city; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_city TO exporter;


--
-- Name: TABLE tab_city_area; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_city_area TO exporter;


--
-- Name: TABLE tab_city_bak0905; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_city_bak0905 TO exporter;


--
-- Name: TABLE tab_city_bak0926; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_city_bak0926 TO exporter;


--
-- Name: TABLE tab_city_bak092601; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_city_bak092601 TO exporter;


--
-- Name: TABLE tab_city_code; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_city_code TO exporter;


--
-- Name: TABLE tab_cmd; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_cmd TO exporter;


--
-- Name: TABLE tab_conf_node; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_conf_node TO exporter;


--
-- Name: TABLE tab_cpe_classify_statistic; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_cpe_classify_statistic TO exporter;


--
-- Name: TABLE tab_cpe_faultcode; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_cpe_faultcode TO exporter;


--
-- Name: TABLE tab_customer_ftth; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_customer_ftth TO exporter;


--
-- Name: TABLE tab_customerinfo; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_customerinfo TO exporter;


--
-- Name: TABLE tab_dev_batch_restart; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_dev_batch_restart TO exporter;


--
-- Name: TABLE tab_dev_black; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_dev_black TO exporter;


--
-- Name: TABLE tab_dev_group; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_dev_group TO exporter;


--
-- Name: TABLE tab_dev_group_import; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_dev_group_import TO exporter;


--
-- Name: TABLE tab_dev_recovery_record; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_dev_recovery_record TO exporter;


--
-- Name: TABLE tab_dev_stack_info; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_dev_stack_info TO exporter;


--
-- Name: TABLE tab_device_bandwidth_rule; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_device_bandwidth_rule TO exporter;


--
-- Name: TABLE tab_device_bandwidth_rule_bak; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_device_bandwidth_rule_bak TO exporter;


--
-- Name: TABLE tab_device_model_attribute; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_device_model_attribute TO exporter;


--
-- Name: TABLE tab_device_model_scrap; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_device_model_scrap TO exporter;


--
-- Name: TABLE tab_device_ty_version; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_device_ty_version TO exporter;


--
-- Name: TABLE tab_device_version_attribute; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_device_version_attribute TO exporter;


--
-- Name: TABLE tab_devicefault; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_devicefault TO exporter;


--
-- Name: TABLE tab_devicemodel_template; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_devicemodel_template TO exporter;


--
-- Name: TABLE tab_devicetype_info; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_devicetype_info TO exporter;


--
-- Name: TABLE tab_devicetype_info_port; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_devicetype_info_port TO exporter;


--
-- Name: TABLE tab_devicetype_info_servertype; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_devicetype_info_servertype TO exporter;


--
-- Name: TABLE tab_devicetype_lan_attr; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_devicetype_lan_attr TO exporter;


--
-- Name: TABLE tab_devicetypetask_info; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_devicetypetask_info TO exporter;


--
-- Name: TABLE tab_diagnosis_iad; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_diagnosis_iad TO exporter;


--
-- Name: TABLE tab_diagnosis_poninfo; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_diagnosis_poninfo TO exporter;


--
-- Name: TABLE tab_diagnosis_voipline; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_diagnosis_voipline TO exporter;


--
-- Name: TABLE tab_diagnosis_wan_conn; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_diagnosis_wan_conn TO exporter;


--
-- Name: TABLE tab_digit_map; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_digit_map TO exporter;


--
-- Name: TABLE tab_egw_bsn_open_original; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_egw_bsn_open_original TO exporter;


--
-- Name: TABLE tab_egw_net_serv_param; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_egw_net_serv_param TO exporter;


--
-- Name: TABLE tab_egw_voip_serv_param; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_egw_voip_serv_param TO exporter;


--
-- Name: TABLE tab_egwcustomer; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_egwcustomer TO exporter;


--
-- Name: TABLE tab_egwcustomer_bak; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_egwcustomer_bak TO exporter;


--
-- Name: TABLE tab_excel_syn_accounts; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_excel_syn_accounts TO exporter;


--
-- Name: TABLE tab_file_server; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_file_server TO exporter;


--
-- Name: TABLE tab_fttr_master_slave; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_fttr_master_slave TO exporter;


--
-- Name: TABLE tab_gather_interface; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_gather_interface TO exporter;


--
-- Name: TABLE tab_group; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_group TO exporter;


--
-- Name: TABLE tab_gw_card; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_gw_card TO exporter;


--
-- Name: TABLE tab_gw_device; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_gw_device TO exporter;


--
-- Name: TABLE tab_gw_device_init; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_gw_device_init TO exporter;


--
-- Name: TABLE tab_gw_device_init_oui; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_gw_device_init_oui TO exporter;


--
-- Name: TABLE tab_gw_device_refuse; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_gw_device_refuse TO exporter;


--
-- Name: TABLE tab_gw_device_scrap; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_gw_device_scrap TO exporter;


--
-- Name: TABLE tab_gw_device_stbmac; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_gw_device_stbmac TO exporter;


--
-- Name: TABLE tab_gw_ht_megabytes; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_gw_ht_megabytes TO exporter;


--
-- Name: TABLE tab_gw_identity; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_gw_identity TO exporter;


--
-- Name: TABLE tab_gw_identity_bak; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_gw_identity_bak TO exporter;


--
-- Name: TABLE tab_gw_oper_type; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_gw_oper_type TO exporter;


--
-- Name: TABLE tab_gw_res_area; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_gw_res_area TO exporter;


--
-- Name: TABLE tab_gw_serv_type; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_gw_serv_type TO exporter;


--
-- Name: TABLE tab_gw_stbid; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_gw_stbid TO exporter;


--
-- Name: TABLE tab_gw_zhijia_device; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_gw_zhijia_device TO exporter;


--
-- Name: TABLE tab_hgw_router; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_hgw_router TO exporter;


--
-- Name: TABLE tab_hgwcustomer; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_hgwcustomer TO exporter;


--
-- Name: TABLE tab_hgwcustomer_bak; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_hgwcustomer_bak TO exporter;


--
-- Name: TABLE tab_hqs_serv_param; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_hqs_serv_param TO exporter;


--
-- Name: TABLE tab_http_diag_result_intf; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_http_diag_result_intf TO exporter;


--
-- Name: TABLE tab_http_simplex_rate; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_http_simplex_rate TO exporter;


--
-- Name: TABLE tab_http_special_speed_intf; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_http_special_speed_intf TO exporter;


--
-- Name: TABLE tab_http_speedtest; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_http_speedtest TO exporter;


--
-- Name: TABLE tab_http_telnet_switch_record; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_http_telnet_switch_record TO exporter;


--
-- Name: TABLE tab_http_test_user; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_http_test_user TO exporter;


--
-- Name: TABLE tab_import_data_temp; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_import_data_temp TO exporter;


--
-- Name: TABLE tab_intf_speed_result; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_intf_speed_result TO exporter;


--
-- Name: TABLE tab_ior; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_ior TO exporter;


--
-- Name: TABLE tab_ipsec_serv_param; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_ipsec_serv_param TO exporter;


--
-- Name: TABLE tab_iptv_serv_param; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_iptv_serv_param TO exporter;


--
-- Name: TABLE tab_iptv_user; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_iptv_user TO exporter;


--
-- Name: TABLE tab_item; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_item TO exporter;


--
-- Name: TABLE tab_item_role; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_item_role TO exporter;


--
-- Name: TABLE tab_lan_speed_report; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_lan_speed_report TO exporter;


--
-- Name: TABLE tab_modify_vlan_task; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_modify_vlan_task TO exporter;


--
-- Name: TABLE tab_modify_vlan_task_dev; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_modify_vlan_task_dev TO exporter;


--
-- Name: TABLE tab_monthgather_device; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_monthgather_device TO exporter;


--
-- Name: TABLE tab_monthgather_device_manual; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_monthgather_device_manual TO exporter;


--
-- Name: TABLE tab_net_serv_param; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_net_serv_param TO exporter;


--
-- Name: TABLE tab_netacc_spead; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_netacc_spead TO exporter;


--
-- Name: TABLE tab_netspeed_param; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_netspeed_param TO exporter;


--
-- Name: TABLE tab_office; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_office TO exporter;


--
-- Name: TABLE tab_oper_log; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_oper_log TO exporter;


--
-- Name: TABLE tab_oss_devicebaseinfo; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_oss_devicebaseinfo TO exporter;


--
-- Name: TABLE tab_oss_dslperformance; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_oss_dslperformance TO exporter;


--
-- Name: TABLE tab_oss_ontinfo; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_oss_ontinfo TO exporter;


--
-- Name: TABLE tab_oss_performance; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_oss_performance TO exporter;


--
-- Name: TABLE tab_oss_wifiassociatedinfo; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_oss_wifiassociatedinfo TO exporter;


--
-- Name: TABLE tab_oss_wifissidinfo; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_oss_wifissidinfo TO exporter;


--
-- Name: TABLE tab_para; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_para TO exporter;


--
-- Name: TABLE tab_para_type; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_para_type TO exporter;


--
-- Name: TABLE tab_performance_alarm; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_performance_alarm TO exporter;


--
-- Name: TABLE tab_performance_mangement; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_performance_mangement TO exporter;


--
-- Name: TABLE tab_permission_collect; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_permission_collect TO exporter;


--
-- Name: TABLE tab_persons; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_persons TO exporter;


--
-- Name: TABLE tab_process; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_process TO exporter;


--
-- Name: TABLE tab_process_config; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_process_config TO exporter;


--
-- Name: TABLE tab_process_desc; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_process_desc TO exporter;


--
-- Name: TABLE tab_quality_issue_analysis; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_quality_issue_analysis TO exporter;


--
-- Name: TABLE tab_quality_issue_analysis_detail; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_quality_issue_analysis_detail TO exporter;


--
-- Name: TABLE tab_quality_issue_fixed_history; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_quality_issue_fixed_history TO exporter;


--
-- Name: TABLE tab_quality_issue_kpi_rule; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_quality_issue_kpi_rule TO exporter;


--
-- Name: TABLE tab_quality_issue_kpi_rule_bak; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_quality_issue_kpi_rule_bak TO exporter;


--
-- Name: TABLE tab_quality_issue_repair_his; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_quality_issue_repair_his TO exporter;


--
-- Name: TABLE tab_quality_issue_suggestion; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_quality_issue_suggestion TO exporter;


--
-- Name: TABLE tab_quality_reboot_task; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_quality_reboot_task TO exporter;


--
-- Name: TABLE tab_register_cpe_origin; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_register_cpe_origin TO exporter;


--
-- Name: TABLE tab_register_cpe_origin_error; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_register_cpe_origin_error TO exporter;


--
-- Name: TABLE tab_register_serv_origin; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_register_serv_origin TO exporter;


--
-- Name: TABLE tab_register_task; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_register_task TO exporter;


--
-- Name: TABLE tab_repair_device_info; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_repair_device_info TO exporter;


--
-- Name: TABLE tab_restartdev; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_restartdev TO exporter;


--
-- Name: TABLE tab_restfulservice_log; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_restfulservice_log TO exporter;


--
-- Name: TABLE tab_role; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_role TO exporter;


--
-- Name: TABLE tab_route_version; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_route_version TO exporter;


--
-- Name: TABLE tab_rpc_match; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_rpc_match TO exporter;


--
-- Name: TABLE tab_seniorquery_tmp; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_seniorquery_tmp TO exporter;


--
-- Name: TABLE tab_serv_classify_statistic; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_serv_classify_statistic TO exporter;


--
-- Name: TABLE tab_serv_template; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_serv_template TO exporter;


--
-- Name: TABLE tab_serv_template_param; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_serv_template_param TO exporter;


--
-- Name: TABLE tab_serv_template_param_bak; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_serv_template_param_bak TO exporter;


--
-- Name: TABLE tab_serv_template_param_bak0725; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_serv_template_param_bak0725 TO exporter;


--
-- Name: TABLE tab_serv_template_param_bak0729; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_serv_template_param_bak0729 TO exporter;


--
-- Name: TABLE tab_serv_template_param_bak0801; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_serv_template_param_bak0801 TO exporter;


--
-- Name: TABLE tab_serv_template_param_bak0802; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_serv_template_param_bak0802 TO exporter;


--
-- Name: TABLE tab_serv_template_param_bak0803; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_serv_template_param_bak0803 TO exporter;


--
-- Name: TABLE tab_serv_template_param_bak0813; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_serv_template_param_bak0813 TO exporter;


--
-- Name: TABLE tab_serv_template_param_bak081302; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_serv_template_param_bak081302 TO exporter;


--
-- Name: TABLE tab_serv_template_param_bak0902; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_serv_template_param_bak0902 TO exporter;


--
-- Name: TABLE tab_serv_template_param_bak0909; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_serv_template_param_bak0909 TO exporter;


--
-- Name: TABLE tab_service; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_service TO exporter;


--
-- Name: TABLE tab_service_sub; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_service_sub TO exporter;


--
-- Name: TABLE tab_servicecode; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_servicecode TO exporter;


--
-- Name: TABLE tab_setmulticast_dev; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_setmulticast_dev TO exporter;


--
-- Name: TABLE tab_setmulticast_task; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_setmulticast_task TO exporter;


--
-- Name: TABLE tab_setmulticast_task_dev; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_setmulticast_task_dev TO exporter;


--
-- Name: TABLE tab_sheet; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_sheet TO exporter;


--
-- Name: TABLE tab_sheet_auth; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_sheet_auth TO exporter;


--
-- Name: TABLE tab_sheet_cmd; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_sheet_cmd TO exporter;


--
-- Name: TABLE tab_sheet_para; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_sheet_para TO exporter;


--
-- Name: TABLE tab_sheet_para_value; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_sheet_para_value TO exporter;


--
-- Name: TABLE tab_sheet_report; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_sheet_report TO exporter;


--
-- Name: TABLE tab_sip_info; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_sip_info TO exporter;


--
-- Name: TABLE tab_soft_upgrade_record; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_soft_upgrade_record TO exporter;


--
-- Name: TABLE tab_software_file; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_software_file TO exporter;


--
-- Name: TABLE tab_softwareup_tmp; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_softwareup_tmp TO exporter;


--
-- Name: TABLE tab_speed_dev_rate; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_speed_dev_rate TO exporter;


--
-- Name: TABLE tab_speed_net; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_speed_net TO exporter;


--
-- Name: TABLE tab_speed_param; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_speed_param TO exporter;


--
-- Name: TABLE tab_stack_task; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_stack_task TO exporter;


--
-- Name: TABLE tab_stack_task_dev; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_stack_task_dev TO exporter;


--
-- Name: TABLE tab_static_src; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_static_src TO exporter;


--
-- Name: TABLE tab_sub_bind_log; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_sub_bind_log TO exporter;


--
-- Name: TABLE tab_summary_data; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_summary_data TO exporter;


--
-- Name: TABLE tab_template; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_template TO exporter;


--
-- Name: TABLE tab_template_cmd; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_template_cmd TO exporter;


--
-- Name: TABLE tab_template_cmd_para; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_template_cmd_para TO exporter;


--
-- Name: TABLE tab_temporary_device; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_temporary_device TO exporter;


--
-- Name: TABLE tab_tree_item; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_tree_item TO exporter;


--
-- Name: TABLE tab_tree_role; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_tree_role TO exporter;


--
-- Name: TABLE tab_tt_alarm; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_tt_alarm TO exporter;


--
-- Name: TABLE tab_tt_alarm_fail; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_tt_alarm_fail TO exporter;


--
-- Name: TABLE tab_upload_log_file_info; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_upload_log_file_info TO exporter;


--
-- Name: TABLE tab_ux_inform_log_bak_20260324121914; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_ux_inform_log_bak_20260324121914 TO exporter;


--
-- Name: TABLE tab_ux_inform_log; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_ux_inform_log TO exporter;


--
-- Name: TABLE tab_ux_inform_log_default; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_ux_inform_log_default TO exporter;


--
-- Name: TABLE tab_ux_inform_log_p20260323; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_ux_inform_log_p20260323 TO exporter;


--
-- Name: TABLE tab_ux_inform_log_p20260324; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_ux_inform_log_p20260324 TO exporter;


--
-- Name: TABLE tab_ux_inform_log_p20260325; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_ux_inform_log_p20260325 TO exporter;


--
-- Name: TABLE tab_ux_inform_log_p20260326; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_ux_inform_log_p20260326 TO exporter;


--
-- Name: TABLE tab_ux_inform_log_p20260327; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_ux_inform_log_p20260327 TO exporter;


--
-- Name: TABLE tab_ux_inform_log_p20260328; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_ux_inform_log_p20260328 TO exporter;


--
-- Name: TABLE tab_ux_inform_log_p20260329; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_ux_inform_log_p20260329 TO exporter;


--
-- Name: TABLE tab_ux_inform_log_p20260330; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_ux_inform_log_p20260330 TO exporter;


--
-- Name: TABLE tab_ux_inform_log_p20260331; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_ux_inform_log_p20260331 TO exporter;


--
-- Name: TABLE tab_ux_inform_log_p20260401; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_ux_inform_log_p20260401 TO exporter;


--
-- Name: TABLE tab_ux_inform_log_p20260402; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_ux_inform_log_p20260402 TO exporter;


--
-- Name: TABLE tab_ux_inform_log_p20260403; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_ux_inform_log_p20260403 TO exporter;


--
-- Name: TABLE tab_ux_inform_log_p20260404; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_ux_inform_log_p20260404 TO exporter;


--
-- Name: TABLE tab_ux_inform_log_p20260405; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_ux_inform_log_p20260405 TO exporter;


--
-- Name: TABLE tab_ux_inform_log_p20260406; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_ux_inform_log_p20260406 TO exporter;


--
-- Name: TABLE tab_ux_inform_log_p20260407; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_ux_inform_log_p20260407 TO exporter;


--
-- Name: TABLE tab_ux_inform_log_p20260408; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_ux_inform_log_p20260408 TO exporter;


--
-- Name: TABLE tab_ux_inform_log_p20260409; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_ux_inform_log_p20260409 TO exporter;


--
-- Name: TABLE tab_ux_inform_log_p20260410; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_ux_inform_log_p20260410 TO exporter;


--
-- Name: TABLE tab_ux_inform_log_p20260411; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_ux_inform_log_p20260411 TO exporter;


--
-- Name: TABLE tab_ux_inform_log_p20260412; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_ux_inform_log_p20260412 TO exporter;


--
-- Name: TABLE tab_ux_inform_log_p20260413; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_ux_inform_log_p20260413 TO exporter;


--
-- Name: TABLE tab_ux_inform_log_p20260414; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_ux_inform_log_p20260414 TO exporter;


--
-- Name: TABLE tab_ux_inform_log_p20260415; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_ux_inform_log_p20260415 TO exporter;


--
-- Name: TABLE tab_ux_inform_log_p20260416; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_ux_inform_log_p20260416 TO exporter;


--
-- Name: TABLE tab_ux_inform_log_p20260417; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_ux_inform_log_p20260417 TO exporter;


--
-- Name: TABLE tab_ux_inform_log_p20260418; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_ux_inform_log_p20260418 TO exporter;


--
-- Name: TABLE tab_ux_inform_log_p20260419; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_ux_inform_log_p20260419 TO exporter;


--
-- Name: TABLE tab_ux_inform_log_p20260420; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_ux_inform_log_p20260420 TO exporter;


--
-- Name: TABLE tab_ux_inform_log_p20260421; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_ux_inform_log_p20260421 TO exporter;


--
-- Name: TABLE tab_ux_inform_log_p20260422; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_ux_inform_log_p20260422 TO exporter;


--
-- Name: TABLE tab_ux_inform_log_p20260423; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_ux_inform_log_p20260423 TO exporter;


--
-- Name: TABLE tab_ux_inform_log_zss; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_ux_inform_log_zss TO exporter;


--
-- Name: TABLE tab_vendor; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_vendor TO exporter;


--
-- Name: TABLE tab_vendor_ieee; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_vendor_ieee TO exporter;


--
-- Name: TABLE tab_vendor_oui; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_vendor_oui TO exporter;


--
-- Name: TABLE tab_vercon_file; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_vercon_file TO exporter;


--
-- Name: TABLE tab_version_type; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_version_type TO exporter;


--
-- Name: TABLE tab_voice_ping_param; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_voice_ping_param TO exporter;


--
-- Name: TABLE tab_voip_serv_param; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_voip_serv_param TO exporter;


--
-- Name: TABLE tab_vxlan_forwarding_config; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_vxlan_forwarding_config TO exporter;


--
-- Name: TABLE tab_vxlan_nat_config; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_vxlan_nat_config TO exporter;


--
-- Name: TABLE tab_vxlan_serv_param; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_vxlan_serv_param TO exporter;


--
-- Name: TABLE tab_whitelist_dev; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_whitelist_dev TO exporter;


--
-- Name: TABLE tab_wirelesst_task; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_wirelesst_task TO exporter;


--
-- Name: TABLE tab_wirelesst_task_dev; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_wirelesst_task_dev TO exporter;


--
-- Name: TABLE tab_xjdx_nomatchreport; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_xjdx_nomatchreport TO exporter;


--
-- Name: TABLE tab_zeroconfig_report; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_zeroconfig_report TO exporter;


--
-- Name: TABLE tab_zeroconfig_res_day; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_zeroconfig_res_day TO exporter;


--
-- Name: TABLE tab_zeroconfig_res_minute; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_zeroconfig_res_minute TO exporter;


--
-- Name: TABLE tab_zone; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.tab_zone TO exporter;


--
-- Name: TABLE user_type; Type: ACL; Schema: public; Owner: gtmsmanager
--

GRANT SELECT ON TABLE public.user_type TO exporter;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: public; Owner: gtmsmanager
--

ALTER DEFAULT PRIVILEGES FOR ROLE gtmsmanager IN SCHEMA public GRANT SELECT ON TABLES TO exporter;


--
-- PostgreSQL database dump complete
--

