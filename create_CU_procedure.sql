CREATE OR REPLACE PROCEDURE create_cu(v_name VARCHAR2) AUTHID CURRENT_USER IS

    TYPE strings IS TABLE OF VARCHAR2(64);
    TYPE fks     IS TABLE OF strings INDEX BY PLS_INTEGER;
    
    pk_cols strings;
    ot_cols strings;
    pk_list VARCHAR2(4000) := '';
    ot_list VARCHAR2(4000) := '';
    
    dep_tables strings;
    dep_tab_fk fks;
    
    trigger_txt VARCHAR2(4000) := '';
    
    PROCEDURE add(txt VARCHAR2) IS
    BEGIN
        trigger_txt := trigger_txt || txt || CHR(10);
    END;
    
    PROCEDURE fill_pks IS
    BEGIN
        SELECT column_name
        BULK COLLECT INTO pk_cols
        FROM user_cons_columns
        WHERE constraint_name IN
            (SELECT constraint_name
             FROM user_constraints
             WHERE constraint_type = 'P' AND
                   table_name = v_name)
        ORDER BY position;
        
        FOR i IN 1..pk_cols.COUNT LOOP
            pk_list := pk_list || pk_cols(i) || ',';
        END LOOP;
        pk_list := TRIM(BOTH ',' FROM pk_list);
    END;
    
    PROCEDURE fill_cols IS
    BEGIN
        SELECT column_name
        BULK COLLECT INTO ot_cols
        FROM user_tab_columns
        WHERE table_name = v_name;
        
        ot_cols := ot_cols MULTISET EXCEPT pk_cols;
        
        FOR i IN 1..ot_cols.COUNT LOOP
            ot_list := ot_list || ot_cols(i) || ',';
        END LOOP;
        ot_list := ','||TRIM(BOTH ',' FROM ot_list);
    END;
    
    PROCEDURE fill_dep_tab IS
    BEGIN
        SELECT DISTINCT table_name
        BULK COLLECT INTO dep_tables
        FROM user_cons_columns
        WHERE constraint_name IN
        (SELECT constraint_name
        FROM user_constraints
        WHERE r_constraint_name =
            (SELECT constraint_name
             FROM user_constraints
             WHERE constraint_type = 'P' AND
                   table_name = v_name));
    END;
    
    PROCEDURE fill_fks IS
    BEGIN
        FOR i IN 1..dep_tables.COUNT LOOP
            SELECT column_name
            BULK COLLECT INTO dep_tab_fk(i)
            FROM user_cons_columns
            WHERE TABLE_NAME = dep_tables(i) AND
            constraint_name IN
            (SELECT constraint_name
            FROM user_constraints
            WHERE r_constraint_name =
                (SELECT constraint_name
                 FROM user_constraints
                 WHERE constraint_type = 'P' AND
                       table_name = v_name))
            ORDER BY POSITION;
        END LOOP;
    END;
BEGIN
        
        fill_pks;
        fill_cols;
        
        IF pk_cols.COUNT > 0 THEN
        
            fill_dep_tab;
            
            IF dep_tables.COUNT > 0 THEN
            
                fill_fks;
        
                add('CREATE OR REPLACE TRIGGER cascade_update_'||v_name);
                add('FOR UPDATE OF '||pk_list||' ON '||v_name);
                add('COMPOUND TRIGGER');
                
                add('idx PLS_INTEGER := 1;');
                
                FOR i IN 1..pk_cols.COUNT LOOP
                    add('TYPE pk'||i||' IS TABLE OF '||v_name||'.'||pk_cols(i)||'%TYPE INDEX BY PLS_INTEGER;');
                    
                    add('new_pk'||i||' pk'||i||';');
                    add('old_pk'||i||' pk'||i||';');
                    add('emp_pk'||i||' pk'||i||';');
                END LOOP;
                
                add('BEFORE STATEMENT IS');
                add('BEGIN');
                FOR i IN 1..pk_cols.COUNT LOOP
                    add('idx := 1;');
                    add('new_pk'||i||' := emp_pk'||i||';');
                    add('old_pk'||i||' := emp_pk'||i||';');
                END LOOP;
                add('END BEFORE STATEMENT;');
                
                add('BEFORE EACH ROW IS');
                add('BEGIN');
                add('IF (');
                FOR i IN 1..pk_cols.COUNT LOOP
                    add(':NEW.'||pk_cols(i)||' <> :OLD.'||pk_cols(i)||' ');
                    IF i <> pk_cols.COUNT THEN
                        add('OR ');
                    END IF;
                END LOOP;
                add(') THEN');
                    FOR i IN 1..pk_cols.COUNT LOOP
                        add('new_pk'||i||'(idx) := :NEW.'||pk_cols(i)||';');
                        add('old_pk'||i||'(idx) := :OLD.'||pk_cols(i)||';');
                        add(':NEW.'||pk_cols(i)||' := :OLD.'||pk_cols(i)||';');
                    END LOOP;
                    add('idx := idx + 1;');
                add('END IF;');
                add('END BEFORE EACH ROW;');
                
                add('AFTER STATEMENT IS');
                add('BEGIN');
                    add('FOR i IN 1..idx-1 LOOP');
                    
                        add('INSERT INTO '||v_name||'('||pk_list||ot_list||')');
                        add('SELECT ');
                        FOR i IN 1..pk_cols.COUNT LOOP
                            add('new_pk'||i||'(i)');
                            IF i <> pk_cols.COUNT THEN add(','); END IF;
                        END LOOP;
                        add(ot_list);
                        add('FROM '||v_name);
                        add('WHERE ('||pk_list||') = (SELECT ');
                        FOR i IN 1..pk_cols.COUNT LOOP
                            IF i <> pk_cols.COUNT THEN
                                add('old_pk'||i||'(i), ');
                            ELSE
                                add('old_pk'||i||'(i) FROM DUAL);');
                            END IF;
                        END LOOP;
                        
                        FOR i IN 1..dep_tables.COUNT LOOP
                            add('UPDATE '||dep_tables(i));
                            add('SET (');
                            FOR j IN 1..dep_tab_fk(i).COUNT LOOP
                                IF j <> dep_tab_fk(i).COUNT THEN
                                    add(dep_tab_fk(i)(j)||',');
                                ELSE
                                    add(dep_tab_fk(i)(j)||')');
                                END IF;
                            END LOOP;
                            add(' = (SELECT ');
                            FOR j IN 1..pk_cols.COUNT LOOP
                                IF j <> pk_cols.COUNT THEN
                                    add('new_pk'||j||'(i),');
                                ELSE
                                    add('new_pk'||j||'(i) FROM DUAL) WHERE (');
                                END IF;
                            END LOOP;
                            FOR j IN 1..dep_tab_fk(i).COUNT LOOP
                                IF j <> dep_tab_fk(i).COUNT THEN
                                    add(dep_tab_fk(i)(j)||',');
                                ELSE
                                    add(dep_tab_fk(i)(j)||')');
                                END IF;
                            END LOOP;
                            add(' = (SELECT ');
                            FOR j IN 1..pk_cols.COUNT LOOP
                                IF j <> pk_cols.COUNT THEN
                                    add('old_pk'||j||'(i),');
                                ELSE
                                    add('old_pk'||j||'(i) FROM DUAL);');
                                END IF;
                            END LOOP;
                        END LOOP;
                        
                        add('DELETE '||v_name);
                        add('WHERE ('||pk_list||') = (SELECT ');
                        FOR j IN 1..pk_cols.COUNT LOOP
                            IF j <> pk_cols.COUNT THEN
                                add('old_pk'||j||'(i),');
                            ELSE
                                add('old_pk'||j||'(i) FROM DUAL);');
                            END IF;
                        END LOOP;
                        
                        
                    add('END LOOP;');
                add('END AFTER STATEMENT;');
            add('END cascade_update_'||v_name||';');
            END IF;
        END IF;
    EXECUTE IMMEDIATE trigger_txt;
END;