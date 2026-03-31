-- ============================================================
-- 【补充索引创建语句】基于字段对比（忽略索引名），墨西哥itmsdb缺少的索引
-- 对照来源: rmsdb-hainan.sql
-- 生成时间: 2026-03-30
-- 说明: 已过滤掉墨西哥中字段相同但索引名不同的重复索引
-- ============================================================


-- 表: gw_cust_user_dev_type
-- 海南索引名: ix_gw_cust_user_dev_type_customer_id  字段: customer_id
CREATE INDEX ix_gw_cust_user_dev_type_customer_id ON public.gw_cust_user_dev_type USING btree (customer_id);


-- 表: gw_device_restart_batch
-- 海南索引名: i_restart_batch_deviceid  字段: device_id
CREATE INDEX i_restart_batch_deviceid ON public.gw_device_restart_batch USING btree (device_id);

-- 海南索引名: i_restart_batch_task_id  字段: task_id
CREATE INDEX i_restart_batch_task_id ON public.gw_device_restart_batch USING btree (task_id);


-- 表: gw_serv_strategy
-- 海南索引名: ix_gw_serv_strategy_time  字段: "time"
CREATE INDEX ix_gw_serv_strategy_time ON public.gw_serv_strategy USING btree ("time");


-- 表: gw_serv_strategy_batch
-- 海南索引名: ix_gw_serv_strategy_batch_dev_id  字段: device_id
CREATE INDEX ix_gw_serv_strategy_batch_dev_id ON public.gw_serv_strategy_batch USING btree (device_id);

-- 海南索引名: ix_gw_serv_strategy_batch_sheet_id  字段: sheet_id
CREATE INDEX ix_gw_serv_strategy_batch_sheet_id ON public.gw_serv_strategy_batch USING btree (sheet_id);

-- 海南索引名: ix_gw_serv_strategy_batch_status  字段: status, type
CREATE INDEX ix_gw_serv_strategy_batch_status ON public.gw_serv_strategy_batch USING btree (status, type);

-- 海南索引名: ix_gw_serv_strategy_batch_temp_id  字段: temp_id
CREATE INDEX ix_gw_serv_strategy_batch_temp_id ON public.gw_serv_strategy_batch USING btree (temp_id);

-- 海南索引名: ix_gw_serv_strategy_batch_time  字段: "time"
CREATE INDEX ix_gw_serv_strategy_batch_time ON public.gw_serv_strategy_batch USING btree ("time");


-- 表: gw_serv_strategy_log
-- 海南索引名: ix_gw_serv_strategy_log_dev_id  字段: device_id
CREATE INDEX ix_gw_serv_strategy_log_dev_id ON public.gw_serv_strategy_log USING btree (device_id);

-- 海南索引名: ix_gw_serv_strategy_log_end_time  字段: end_time
CREATE INDEX ix_gw_serv_strategy_log_end_time ON public.gw_serv_strategy_log USING btree (end_time);

-- 海南索引名: ix_gw_serv_strategy_log_status  字段: status, type
CREATE INDEX ix_gw_serv_strategy_log_status ON public.gw_serv_strategy_log USING btree (status, type);


-- 表: gw_serv_strategy_serv_log
-- 海南索引名: ix_gw_serv_strategy_serv_log_end_time  字段: end_time
CREATE INDEX ix_gw_serv_strategy_serv_log_end_time ON public.gw_serv_strategy_serv_log USING btree (end_time);


-- 表: hgwcust_serv_info
-- 海南索引名: ix_hgwcust_serv_info_username  字段: username
CREATE INDEX ix_hgwcust_serv_info_username ON public.hgwcust_serv_info USING btree (username);


-- 表: stb_tab_customer
-- 海南索引名: ix_stb_customer_account  字段: cust_account
CREATE INDEX ix_stb_customer_account ON public.stb_tab_customer USING btree (cust_account);

-- 海南索引名: ix_stb_customer_mac  字段: cpe_mac
CREATE INDEX ix_stb_customer_mac ON public.stb_tab_customer USING btree (cpe_mac);

-- 海南索引名: ix_stb_customer_pppoeuser  字段: pppoe_user
CREATE INDEX ix_stb_customer_pppoeuser ON public.stb_tab_customer USING btree (pppoe_user);

-- 海南索引名: ix_stb_customer_query  字段: city_id, user_status, user_grp, openuserdate
CREATE INDEX ix_stb_customer_query ON public.stb_tab_customer USING btree (city_id, user_status, user_grp, openuserdate);

-- 海南索引名: ix_stb_customer_serv  字段: serv_account
CREATE INDEX ix_stb_customer_serv ON public.stb_tab_customer USING btree (serv_account);

-- 海南索引名: ix_stb_customer_sn  字段: sn
CREATE INDEX ix_stb_customer_sn ON public.stb_tab_customer USING btree (sn);

-- 海南索引名: ix_stb_customer_stat  字段: cust_stat
CREATE INDEX ix_stb_customer_stat ON public.stb_tab_customer USING btree (cust_stat);

-- 海南索引名: ix_stb_customer_status  字段: user_status
CREATE INDEX ix_stb_customer_status ON public.stb_tab_customer USING btree (user_status);


-- 表: stb_tab_gw_device
-- 海南索引名: ix_stb_device_ip_six  字段: loopback_ip_six
CREATE INDEX ix_stb_device_ip_six ON public.stb_tab_gw_device USING btree (loopback_ip_six);

-- 海南索引名: ix_stb_device_model_id  字段: device_model_id
CREATE INDEX ix_stb_device_model_id ON public.stb_tab_gw_device USING btree (device_model_id);

-- 海南索引名: ix_stb_device_serv_account  字段: serv_account
CREATE INDEX ix_stb_device_serv_account ON public.stb_tab_gw_device USING btree (serv_account);

-- 海南索引名: ix_stb_device_vendor_id  字段: vendor_id
CREATE INDEX ix_stb_device_vendor_id ON public.stb_tab_gw_device USING btree (vendor_id);


-- 表: tab_batch_task_dev
-- 海南索引名: ix_batch_task_dev_devid_status  字段: device_id, status
CREATE INDEX ix_batch_task_dev_devid_status ON public.tab_batch_task_dev USING btree (device_id, status);

-- 海南索引名: ix_batch_task_dev_status  字段: status
CREATE INDEX ix_batch_task_dev_status ON public.tab_batch_task_dev USING btree (status);

-- 海南索引名: ix_batch_task_dev_taskid  字段: task_id
CREATE INDEX ix_batch_task_dev_taskid ON public.tab_batch_task_dev USING btree (task_id);


-- 表: tab_batch_task_info
-- 海南索引名: ix_batch_task_info_add_time  字段: add_time
CREATE INDEX ix_batch_task_info_add_time ON public.tab_batch_task_info USING btree (add_time);

-- 海南索引名: ix_batch_task_info_task_status  字段: task_status
CREATE INDEX ix_batch_task_info_task_status ON public.tab_batch_task_info USING btree (task_status);


-- 表: tab_batchhttp_task_dev
-- 海南索引名: i_speedtask_pppname  字段: pppoe_name
CREATE INDEX i_speedtask_pppname ON public.tab_batchhttp_task_dev USING btree (pppoe_name);


-- 表: tab_bss_sheet
-- 海南索引名: ix_bss_sheet_order_spec_id  字段: order_id, product_spec_id
CREATE INDEX ix_bss_sheet_order_spec_id ON public.tab_bss_sheet USING btree (order_id, product_spec_id);


-- 表: tab_customerinfo
-- 海南索引名: i_customerinfo_cust_name  字段: customer_name
CREATE INDEX i_customerinfo_cust_name ON public.tab_customerinfo USING btree (customer_name);


-- 表: tab_dev_batch_restart
-- 海南索引名: ix_tab_dev_batch_restart_deviceid  字段: device_id
CREATE INDEX ix_tab_dev_batch_restart_deviceid ON public.tab_dev_batch_restart USING btree (device_id);

-- 海南索引名: ix_tab_dev_batch_restart_tastid  字段: task_id
CREATE INDEX ix_tab_dev_batch_restart_tastid ON public.tab_dev_batch_restart USING btree (task_id);


-- 表: tab_egwcustomer
-- 海南索引名: ix_egwcustomer_username  字段: username
CREATE INDEX ix_egwcustomer_username ON public.tab_egwcustomer USING btree (username);


-- 表: tab_egwcustomer_bak
-- 海南索引名: ix_egwcustomer_bak_username  字段: username
CREATE INDEX ix_egwcustomer_bak_username ON public.tab_egwcustomer_bak USING btree (username);


-- 表: tab_fttr_master_slave
-- 海南索引名: ix_tab_fttr_master_slave_master_devid  字段: master_device_id
CREATE INDEX ix_tab_fttr_master_slave_master_devid ON public.tab_fttr_master_slave USING btree (master_device_id);

-- 海南索引名: ix_tab_fttr_master_slave_master_mac  字段: master_mac
CREATE INDEX ix_tab_fttr_master_slave_master_mac ON public.tab_fttr_master_slave USING btree (master_mac);

-- 海南索引名: ix_tab_fttr_master_slave_slave_oui  字段: slave_oui
CREATE INDEX ix_tab_fttr_master_slave_slave_oui ON public.tab_fttr_master_slave USING btree (slave_oui);


-- 表: tab_gw_device_stbmac
-- 海南索引名: i_tab_gw_device_stbmac_devid  字段: device_id, stb_mac
CREATE INDEX i_tab_gw_device_stbmac_devid ON public.tab_gw_device_stbmac USING btree (device_id, stb_mac);

-- 海南索引名: i_tab_gw_device_stbmac_stb_mac  字段: stb_mac
CREATE INDEX i_tab_gw_device_stbmac_stb_mac ON public.tab_gw_device_stbmac USING btree (stb_mac);


-- 表: tab_hgwcustomer
-- 海南索引名: i_oui_sn  字段: oui, device_serialnumber
CREATE INDEX i_oui_sn ON public.tab_hgwcustomer USING btree (oui, device_serialnumber);

-- 海南索引名: u_tab_hgwcustomer_username  字段: [UNIQUE] username
CREATE UNIQUE INDEX u_tab_hgwcustomer_username ON public.tab_hgwcustomer USING btree (username);


-- 表: tab_http_telnet_switch_record
-- 海南索引名: idx_action  字段: action
CREATE INDEX idx_action ON public.tab_http_telnet_switch_record USING btree (action);

-- 海南索引名: idx_record_time  字段: record_time
CREATE INDEX idx_record_time ON public.tab_http_telnet_switch_record USING btree (record_time);


-- 表: tab_net_serv_param
-- 海南索引名: i_tab_net_serv_param_user_id  字段: user_id
CREATE INDEX i_tab_net_serv_param_user_id ON public.tab_net_serv_param USING btree (user_id);

-- 海南索引名: i_tab_net_serv_param_user_serv_username  字段: user_id, username, serv_type_id
CREATE INDEX i_tab_net_serv_param_user_serv_username ON public.tab_net_serv_param USING btree (user_id, username, serv_type_id);


-- 表: tab_summary_data
-- 海南索引名: index_tab_summary_data_cityname  字段: cityname
CREATE INDEX index_tab_summary_data_cityname ON public.tab_summary_data USING btree (cityname);

-- 海南索引名: index_tab_summary_data_deviceid  字段: deviceid
CREATE INDEX index_tab_summary_data_deviceid ON public.tab_summary_data USING btree (deviceid);


-- 表: tab_voip_serv_param
-- 海南索引名: i_tab_voip_serv_param_user_id  字段: user_id
CREATE INDEX i_tab_voip_serv_param_user_id ON public.tab_voip_serv_param USING btree (user_id);

-- 海南索引名: i_tab_voip_serv_param_user_id_line_id  字段: user_id, line_id
CREATE INDEX i_tab_voip_serv_param_user_id_line_id ON public.tab_voip_serv_param USING btree (user_id, line_id);


-- ============================================================
-- 【补充存储过程/函数】海南有而墨西哥缺少的
-- ============================================================

-- 函数/过程: gettgwmodeltypeidproc
CREATE PROCEDURE public.gettgwmodeltypeidproc(IN p_oui character varying, IN p_manufacturer character varying, IN p_device_model character varying, IN p_specversion character varying, IN p_hardwareversion character varying, IN p_softwareversion character varying, INOUT p_vendor_id integer, INOUT p_device_model_id integer, INOUT p_devicetype_id integer)
    LANGUAGE plpgsql
    AS $_$
DECLARE
    v_vendor_id          VARCHAR(10); 
    v_device_model_id    VARCHAR(10); 
    v_devicetype_id      INTEGER;
    v_add_time          BIGINT;
    v_count             INTEGER;
BEGIN
    v_vendor_id := '0';
    v_device_model_id := '0';
    v_devicetype_id := 0;
    v_count := 0;

   v_add_time := EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP AT TIME ZONE 'UTC' - TIMESTAMP '1970-01-01 00:00:00 UTC'));

    -- 1. 查询v_vendor_id
    EXECUTE 'SELECT COUNT(*) FROM tab_vendor WHERE vendor_name = $1' INTO v_count USING p_manufacturer;
    IF v_count = 0 THEN
        EXECUTE 'SELECT COALESCE(MAX(CAST(vendor_id AS INTEGER)), 0) + 1 FROM tab_vendor' INTO v_vendor_id;
        EXECUTE 'INSERT INTO tab_vendor(vendor_id, vendor_name, vendor_add, add_time) VALUES ($1, $2, $2, $3)' 
        USING v_vendor_id, p_manufacturer, v_add_time;
        COMMIT;
    ELSE
        EXECUTE 'SELECT vendor_id FROM tab_vendor WHERE vendor_name = $1' INTO v_vendor_id USING p_manufacturer;
    END IF;

    -- 2. 查询oui
    v_count := 0;
    EXECUTE 'SELECT COUNT(*) FROM tab_vendor_oui WHERE vendor_id = $1 AND oui = $2' INTO v_count USING v_vendor_id, p_oui;
    IF v_count = 0 THEN
        EXECUTE 'INSERT INTO tab_vendor_oui(vendor_id, oui) VALUES ($1, $2)' USING v_vendor_id, p_oui;
        COMMIT;
    END IF;

    -- 3. 查询gw_device_model
    v_count := 0;
    EXECUTE 'SELECT COUNT(*) FROM gw_device_model WHERE vendor_id = $1 AND device_model = $2' INTO v_count USING v_vendor_id, p_device_model;
    IF v_count = 0 THEN
        EXECUTE 'SELECT COALESCE(MAX(CAST(device_model_id AS INTEGER)), 0) + 1 FROM gw_device_model' INTO v_device_model_id;
        EXECUTE 'INSERT INTO gw_device_model(device_model_id, vendor_id, device_model, add_time) VALUES ($1, $2, $3, $4)' 
        USING v_device_model_id, v_vendor_id, p_device_model, v_add_time;
        COMMIT;
    ELSE
        EXECUTE 'SELECT device_model_id FROM gw_device_model WHERE vendor_id = $1 AND device_model = $2' INTO v_device_model_id USING v_vendor_id, p_device_model;
    END IF;

    -- 4. 查询tab_devicetype_info
    v_count := 0;
    EXECUTE 'SELECT COUNT(*) FROM tab_devicetype_info WHERE vendor_id = $1 AND device_model_id = $2 AND softwareversion = $3 AND hardwareversion = $4' INTO v_count 
    USING v_vendor_id, v_device_model_id, p_softwareversion, p_hardwareversion;
    IF v_count = 0 THEN
        EXECUTE 'SELECT COALESCE(MAX(devicetype_id), 0) + 1 FROM tab_devicetype_info' INTO v_devicetype_id;
        EXECUTE 'INSERT INTO tab_devicetype_info(devicetype_id, vendor_id, device_model_id, specversion, hardwareversion, softwareversion, add_time) VALUES ($1, $2, $3, $4, $5, $6, $7)' 
        USING v_devicetype_id, v_vendor_id, v_device_model_id, p_specversion, p_hardwareversion, p_softwareversion, v_add_time;
        COMMIT;
    ELSE
        EXECUTE 'SELECT devicetype_id FROM tab_devicetype_info WHERE vendor_id = $1 AND device_model_id = $2 AND softwareversion = $3 AND hardwareversion = $4' INTO v_devicetype_id 
        USING v_vendor_id, v_device_model_id, p_softwareversion, p_hardwareversion;
    END IF;

    -- 直接给INOUT参数赋值
    p_vendor_id := v_vendor_id::INTEGER; 
    p_device_model_id := v_device_model_id::INTEGER; 
    p_devicetype_id := v_devicetype_id;

END;
$_$;


--
-- Name: maxbindlogidproc(integer, bigint); Type: PROCEDURE; Schema: rms; Owner: -
--

CREATE PROCEDURE public.maxbindlogidproc(IN counts integer, INOUT maxid bigint)
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- 假设maxResID是一个已存在的过程或函数，接受三个参数，第一个参数为1表示获取设备ID
    CALL maxResID(12, counts, maxId);
END;
$$;

-- 函数/过程: maxhgwuseridproc
CREATE PROCEDURE public.maxhgwuseridproc(IN counts integer, INOUT maxid bigint)
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- 假设maxResID是一个已存在的过程或函数，接受三个参数，第一个参数为1表示获取设备ID
    CALL maxResID(11, counts, maxId);
END;
$$;

-- 函数/过程: maxstrategyidproc
CREATE PROCEDURE public.maxstrategyidproc(IN counts integer, INOUT maxid bigint)
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- 假设maxResID是一个已存在的过程或函数，接受三个参数，第一个参数为1表示获取设备ID
    CALL maxResID(13, counts, maxId);
END;
$$;

-- 函数/过程: maxtr069deviceidproc
CREATE PROCEDURE public.maxtr069deviceidproc(IN counts integer, INOUT maxid bigint)
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- 假设maxResID是一个已存在的过程或函数，接受三个参数，第一个参数为1表示获取设备ID
    CALL maxResID(1, counts, maxId);
END;
$$;
