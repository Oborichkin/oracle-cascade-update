CREATE OR REPLACE TRIGGER create_cascade_update
    AFTER CREATE ON SCHEMA
DECLARE
    TYPE strings IS TABLE OF VARCHAR2(64);
    
    v_type VARCHAR2(64) := UPPER(SYS.DICTIONARY_OBJ_TYPE);
    v_name VARCHAR2(64) := UPPER(SYS.DICTIONARY_OBJ_NAME);
    
    parent_tabs strings;
BEGIN
    IF v_type = 'TABLE' THEN
        SELECT DISTINCT TABLE_NAME
        BULK COLLECT INTO parent_tabs
        FROM USER_CONSTRAINTS
        WHERE CONSTRAINT_NAME IN
            (SELECT R_CONSTRAINT_NAME
             FROM USER_CONSTRAINTS
             WHERE CONSTRAINT_TYPE = 'R'
             AND TABLE_NAME = v_name);
             
        FOR i IN 1..parent_tabs.COUNT LOOP
            DBMS_SCHEDULER.CREATE_JOB (
                job_name   => 'create_trigger_'||parent_tabs(i),
                job_type   => 'PLSQL_BLOCK',
                job_action => q'[BEGIN create_cu(']'||parent_tabs(i)||q'['); END;]',
                start_date => SYSDATE + 1/(1440),
                repeat_interval => 'FREQ=MINUTELY;INTERVAL=1',
                end_date        => SYSDATE + 1.1/(1440),
                enabled         => TRUE,
                comments        => 'create cascade update');
        END LOOP;
    END IF;
END create_cascade_update;

CREATE OR REPLACE TRIGGER alter_cascade_update
    AFTER ALTER ON SCHEMA
DECLARE
    TYPE strings IS TABLE OF VARCHAR2(64);
    
    v_type VARCHAR2(64) := UPPER(SYS.DICTIONARY_OBJ_TYPE);
    v_name VARCHAR2(64) := UPPER(SYS.DICTIONARY_OBJ_NAME);
    
    parent_tabs strings;
    temp NUMBER;
BEGIN
    IF v_type = 'TABLE' THEN
        SELECT COUNT(*)
        INTO temp
        FROM USER_CONSTRAINTS
        WHERE TABLE_NAME = v_name AND
              CONSTRAINT_TYPE = 'P';
        
        IF SQL%FOUND THEN
            DBMS_SCHEDULER.CREATE_JOB (
                job_name   => 'create_trigger_'||v_name,
                job_type   => 'PLSQL_BLOCK',
                job_action => q'[BEGIN create_cu(']'||UPPER(v_name)||q'['); END;]',
                start_date => SYSDATE + 1/(1440),
                repeat_interval => 'FREQ=MINUTELY;INTERVAL=1',
                end_date        => SYSDATE + 1.1/(1440),
                enabled         => TRUE,
                comments        => 'create cascade update');
        END IF;
        
        SELECT DISTINCT TABLE_NAME
        BULK COLLECT INTO parent_tabs
        FROM USER_CONSTRAINTS
        WHERE CONSTRAINT_NAME IN
            (SELECT R_CONSTRAINT_NAME
             FROM USER_CONSTRAINTS
             WHERE CONSTRAINT_TYPE = 'R'
             AND TABLE_NAME = v_name);
        FOR i IN 1..parent_tabs.COUNT LOOP
            DBMS_SCHEDULER.CREATE_JOB (
                job_name   => 'create_trigger_'||parent_tabs(i),
                job_type   => 'PLSQL_BLOCK',
                job_action => q'[BEGIN create_cu(']'||parent_tabs(i)||q'['); END;]',
                start_date => SYSDATE + 1/(1440),
                repeat_interval => 'FREQ=MINUTELY;INTERVAL=1',
                end_date        => SYSDATE + 1.1/(1440),
                enabled         => TRUE,
                comments        => 'create cascade update');
        END LOOP;
    END IF;
END create_cascade_update;