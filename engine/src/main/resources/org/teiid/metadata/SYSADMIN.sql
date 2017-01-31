CREATE FOREIGN TABLE Usage (
    VDBName string(255) NOT NULL,
    UID string(50) NOT NULL,
    object_type string(50) NOT NULL,
    SchemaName string(255) NOT NULL,
    Name string(255) NOT NULL,
    ElementName string(255),
    Uses_UID string(50) NOT NULL,
    Uses_object_type string(50) NOT NULL,
    Uses_SchemaName string(255) NOT NULL,
    Uses_Name string(255) NOT NULL,
    Uses_ElementName string(255),
    PRIMARY KEY (UID, Uses_UID)
);

CREATE FOREIGN TABLE MatViews (
	VDBName string(255) NOT NULL,
	SchemaName string(255) NOT NULL,
	Name string(255) NOT NULL,
	TargetSchemaName string(255),
	TargetName string,
	Valid boolean,
	LoadState string(255),
	Updated timestamp,
	Cardinality integer,
	PRIMARY KEY (VDBName, SchemaName, Name)
);

CREATE FOREIGN TABLE VDBResources (
	resourcePath string(255),
	contents blob,
	PRIMARY KEY (resourcePath)
);

CREATE FOREIGN TABLE Triggers (
	VDBName string(255) NOT NULL,
	SchemaName string(255) NOT NULL,
	TableName string(255) NOT NULL,
	Name string(255) NOT NULL,
	TriggerType string(50) NOT NULL,
	TriggerEvent string(50) NOT NULL,
	Status string(50) NOT NULL,
	Body clob(2097152),
	TableUID string(50) NOT NULL,
	PRIMARY KEY (VDBName, SchemaName, TableName, Name)
);

CREATE FOREIGN TABLE Views (
    VDBName string(255) NOT NULL,
    SchemaName string(255) NOT NULL,
    Name string(255) NOT NULL,
    Body clob(2097152) NOT NULL,
    UID string(50) NOT NULL,
    PRIMARY KEY (VDBName, SchemaName, Name),
    UNIQUE(UID)
);

CREATE FOREIGN TABLE StoredProcedures (
    VDBName string(255) NOT NULL,
    SchemaName string(255) NOT NULL,
    Name string(255) NOT NULL,
    Body clob(2097152) NOT NULL,
    UID string(50) NOT NULL,
    PRIMARY KEY (VDBName, SchemaName, Name),
    UNIQUE(UID)
);

CREATE FOREIGN PROCEDURE isLoggable(OUT loggable boolean NOT NULL RESULT, IN level string NOT NULL DEFAULT 'DEBUG', IN context string NOT NULL DEFAULT 'org.teiid.PROCESSOR')
OPTIONS (UPDATECOUNT 0)

CREATE FOREIGN PROCEDURE logMsg(OUT logged boolean NOT NULL RESULT, IN level string NOT NULL DEFAULT 'DEBUG', IN context string NOT NULL DEFAULT 'org.teiid.PROCESSOR', IN msg object NOT NULL)
OPTIONS (UPDATECOUNT 0)

CREATE FOREIGN PROCEDURE refreshMatView(OUT RowsUpdated integer NOT NULL RESULT, IN ViewName string NOT NULL, IN Invalidate boolean NOT NULL DEFAULT 'false')
OPTIONS (UPDATECOUNT 0)

CREATE FOREIGN PROCEDURE refreshMatViewRow(OUT RowsUpdated integer NOT NULL RESULT, IN ViewName string NOT NULL, IN Key object NOT NULL, VARIADIC KeyOther object)
OPTIONS (UPDATECOUNT 1)

CREATE FOREIGN PROCEDURE refreshMatViewRows(OUT RowsUpdated integer NOT NULL RESULT, IN ViewName string NOT NULL, VARIADIC Key object[] NOT NULL)
OPTIONS (UPDATECOUNT 1)

CREATE FOREIGN PROCEDURE setColumnStats(IN tableName string NOT NULL, IN columnName string NOT NULL, IN distinctCount long, IN nullCount long, IN max string, IN min string)
OPTIONS (UPDATECOUNT 0)

CREATE FOREIGN PROCEDURE setProperty(OUT OldValue clob(2097152) NOT NULL RESULT, IN UID string(50) NOT NULL, IN Name string NOT NULL, IN "Value" clob(2097152))
OPTIONS (UPDATECOUNT 0)

CREATE FOREIGN PROCEDURE setTableStats(IN tableName string NOT NULL, IN cardinality long NOT NULL)
OPTIONS (UPDATECOUNT 0)

CREATE VIRTUAL PROCEDURE matViewStatus(IN schemaName string NOT NULL, IN viewName string NOT NULL) RETURNS TABLE (TargetSchemaName varchar(50), TargetName varchar(50), Valid boolean, LoadState varchar(25), Updated timestamp, Cardinality long, LoadNumber long, OnErrorAction varchar(25)) AS
BEGIN
	DECLARE string vdbName = (SELECT Name FROM VirtualDatabases);
	DECLARE integer vdbVersion = (SELECT convert(Version, integer) FROM VirtualDatabases);
	DECLARE string uid = (SELECT UID FROM Sys.Tables WHERE VDBName = VARIABLES.vdbName AND SchemaName = matViewStatus.schemaName AND Name = matViewStatus.viewName);
	
	IF (uid IS NULL)
	BEGIN
		RAISE SQLEXCEPTION 'The view was not found';
	END
	
	DECLARE boolean isMaterialized = (SELECT IsMaterialized FROM SYS.Tables WHERE UID = VARIABLES.uid);
	
	IF (NOT isMaterialized)
	BEGIN
		RAISE SQLEXCEPTION 'The view is not declared as Materialized View in Metadata';
	END		  

	DECLARE string statusTable = (SELECT "Value" from SYS.Properties WHERE UID = VARIABLES.uid AND Name = '{http://www.teiid.org/ext/relational/2012}MATVIEW_STATUS_TABLE');
	DECLARE string action = (SELECT "Value" from SYS.Properties WHERE UID = VARIABLES.uid AND Name = '{http://www.teiid.org/ext/relational/2012}MATVIEW_ONERROR_ACTION');
	DECLARE string crit = ' WHERE VDBName = DVARS.vdbName AND VDBVersion = DVARS.vdbVersion AND schemaName = DVARS.schemaName AND Name = DVARS.viewName';

	EXECUTE IMMEDIATE 'SELECT TargetSchemaName, TargetName, Valid, LoadState, Updated, Cardinality, LoadNumber, VARIABLES.action FROM ' || VARIABLES.statusTable || crit AS TargetSchemaName string, TargetName string, Valid boolean, LoadState string, Updated timestamp, Cardinality long, LoadNumber long, OnErrorAction varchar(25) USING vdbName = VARIABLES.vdbName, vdbVersion = VARIABLES.vdbVersion, schemaName = matViewStatus.schemaName, viewName = matViewStatus.viewName;
END


CREATE VIRTUAL PROCEDURE loadMatView(IN schemaName string NOT NULL, IN viewName string NOT NULL, IN invalidate boolean NOT NULL DEFAULT 'false') RETURNS integer
AS
BEGIN
	DECLARE string vdbName = (SELECT Name FROM VirtualDatabases);
	DECLARE integer vdbVersion = (SELECT convert(Version, integer) FROM VirtualDatabases);
	DECLARE string uid = (SELECT UID FROM Sys.Tables WHERE VDBName = VARIABLES.vdbName AND SchemaName = loadMatView.schemaName AND Name = loadMatView.viewName);
	DECLARE string status = 'CHECK';
	DECLARE integer rowsUpdated = 0;
	DECLARE string crit;
	DECLARE integer lineCount = 0;
	DECLARE integer index = 0;
	
	IF (uid IS NULL)
	BEGIN
		RAISE SQLEXCEPTION 'The view was not found';
	END
	
	DECLARE boolean isMaterialized = (SELECT IsMaterialized FROM SYS.Tables WHERE UID = VARIABLES.uid);
	
	IF (NOT isMaterialized)
	BEGIN
		RAISE SQLEXCEPTION 'The view is not declared as Materialized View in Metadata';
	END		  

	DECLARE string statusTable = (SELECT "value" from SYS.Properties WHERE UID = VARIABLES.uid AND Name = '{http://www.teiid.org/ext/relational/2012}MATVIEW_STATUS_TABLE');
	DECLARE string beforeLoadScript = (SELECT "value" from SYS.Properties WHERE UID = VARIABLES.uid AND Name = '{http://www.teiid.org/ext/relational/2012}MATVIEW_BEFORE_LOAD_SCRIPT');
	DECLARE string loadScript = (SELECT "value" from SYS.Properties WHERE UID = VARIABLES.uid AND Name = '{http://www.teiid.org/ext/relational/2012}MATVIEW_LOAD_SCRIPT');
	DECLARE string afterLoadScript = (SELECT "value" from SYS.Properties WHERE UID = VARIABLES.uid AND Name = '{http://www.teiid.org/ext/relational/2012}MATVIEW_AFTER_LOAD_SCRIPT');
	DECLARE integer ttl = (SELECT convert("value", integer) from SYS.Properties WHERE UID = VARIABLES.uid AND Name = '{http://www.teiid.org/ext/relational/2012}MATVIEW_TTL');
	DECLARE string matViewStageTable = (SELECT "value" from SYS.Properties WHERE UID = VARIABLES.uid AND Name = '{http://www.teiid.org/ext/relational/2012}MATERIALIZED_STAGE_TABLE');	
	DECLARE string scope = (SELECT "value" from SYS.Properties WHERE UID = VARIABLES.uid AND Name = '{http://www.teiid.org/ext/relational/2012}MATVIEW_SHARE_SCOPE');
	DECLARE string[] targets = (SELECT (TargetName, TargetSchemaName) from SYSADMIN.MatViews WHERE VDBName = VARIABLES.vdbName AND SchemaName = loadMatView.schemaName AND Name = loadMatView.viewName);
	DECLARE string matViewTable = array_get(targets, 1);
	DECLARE string targetSchemaName = array_get(targets, 2);
	DECLARE string action = (SELECT "Value" from SYS.Properties WHERE UID = VARIABLES.uid AND Name = '{http://www.teiid.org/ext/relational/2012}MATVIEW_ONERROR_ACTION');
	DECLARE boolean implicitLoadScript = false;
	
	IF ((scope IS null) OR (scope = 'NONE'))
	BEGIN 
		VARIABLES.crit = ' WHERE VDBName = DVARS.vdbName AND VDBVersion = DVARS.vdbVersion AND schemaName = DVARS.schemaName AND Name = DVARS.viewName';
	END
	ELSE IF (scope = 'VDB')
	BEGIN
		VARIABLES.crit = ' WHERE VDBName = DVARS.vdbName AND schemaName = DVARS.schemaName AND Name = DVARS.viewName';
	END
	ELSE IF (scope = 'SCHEMA')
	BEGIN
		VARIABLES.crit = ' WHERE schemaName = DVARS.schemaName AND Name = DVARS.viewName';
	END

	DECLARE string updateStmt = 'UPDATE ' || VARIABLES.statusTable || ' SET LoadNumber = DVARS.LoadNumber, LoadState = DVARS.LoadState, valid = DVARS.valid, Updated = DVARS.updated, Cardinality = DVARS.cardinality' ||  crit;

	EXECUTE IMMEDIATE 'SELECT Name, TargetSchemaName, TargetName, Valid, LoadState, Updated, Cardinality, LoadNumber FROM ' || VARIABLES.statusTable || crit AS Name string, TargetSchemaName string, TargetName string, Valid boolean, LoadState string, Updated timestamp, Cardinality long, LoadNumber long INTO #load USING vdbName = VARIABLES.vdbName, vdbVersion = VARIABLES.vdbVersion, schemaName = schemaName, viewName = loadMatView.viewName;
	
	DECLARE string previousRow = (SELECT Name FROM #load);
	IF (previousRow is null)
    BEGIN 
        EXECUTE IMMEDIATE 'INSERT INTO '|| VARIABLES.statusTable ||' (VDBName, VDBVersion, SchemaName, Name, TargetSchemaName, TargetName, Valid, LoadState, Updated, Cardinality, LoadNumber) values (DVARS.vdbName, DVARS.vdbVersion, DVARS.schemaName, DVARS.viewName, DVARS.TargetSchemaName, DVARS.matViewTable, DVARS.valid, DVARS.loadStatus, DVARS.updated, -1, 1)' USING vdbName = VARIABLES.vdbName, vdbVersion = VARIABLES.vdbVersion, schemaName = schemaName, targetSchemaName = VARIABLES.targetSchemaName, viewName = loadMatView.viewName, valid=false, loadStatus='LOADING', matViewTable=matViewTable, updated = now();
        VARIABLES.status = 'LOAD';
    EXCEPTION e
        DELETE FROM #load;
        EXECUTE logMsg(context=>'org.teiid.MATVIEWS', level=>'WARN', msg=>e.exception);
        EXECUTE IMMEDIATE 'SELECT Name, TargetSchemaName, TargetName, Valid, LoadState, Updated, Cardinality, LoadNumber FROM ' || VARIABLES.statusTable || crit AS Name string, TargetSchemaName string, TargetName string, Valid boolean, LoadState string, Updated timestamp, Cardinality long, LoadNumber long INTO #load USING vdbName = VARIABLES.vdbName, vdbVersion = VARIABLES.vdbVersion, schemaName = schemaName, viewName = loadMatView.viewName;		       
    END
    
    DECLARE long VARIABLES.loadNumber = 1;
    DECLARE boolean VARIABLES.valid = false;
	
	IF (VARIABLES.status = 'CHECK')
	BEGIN 
	    LOOP ON (SELECT valid, updated, loadstate, cardinality, loadnumber FROM #load) AS matcursor
	    BEGIN
		    IF (loadstate <> 'LOADING' OR TIMESTAMPDIFF(SQL_TSI_SECOND, matcursor.updated, now()) > (ttl/1000))
		        BEGIN 
		            EXECUTE IMMEDIATE updateStmt || ' AND loadNumber = ' || matcursor.loadNumber USING loadNumber = matcursor.loadNumber + 1, vdbName = VARIABLES.vdbName, vdbVersion = VARIABLES.vdbVersion, schemaName = schemaName, viewName = loadMatView.viewName, updated = now(), LoadState = 'LOADING', valid = matcursor.valid AND NOT invalidate, cardinality = matcursor.cardinality;
					DECLARE integer updated = VARIABLES.ROWCOUNT;
					IF (updated = 0)
						BEGIN
							VARIABLES.status = 'DONE';
							VARIABLES.rowsUpdated = -1;
						END
					ELSE
						BEGIN					            
				            VARIABLES.status = 'LOAD';
				            VARIABLES.loadNumber = matcursor.loadNumber + 1;
				            VARIABLES.valid = matcursor.valid;
			            END				
		        END
	        ELSE
		        BEGIN
	                IF (invalidate AND matcursor.valid)
                        EXECUTE IMMEDIATE 'UPDATE ' || VARIABLES.statusTable || ' SET valid = false ' || crit || ' AND loadNumber = ' || matcursor.loadNumber USING vdbName = VARIABLES.vdbName, vdbVersion = VARIABLES.vdbVersion, schemaName = schemaName, viewName = loadMatView.viewName;
		        	VARIABLES.rowsUpdated = -1;
		        	VARIABLES.status = 'DONE';
		        END
	    END
    END
	
    IF(VARIABLES.status = 'LOAD')
    BEGIN ATOMIC
    	IF (VARIABLES.loadScript IS null)
    	BEGIN
    	    DECLARE string columns = (SELECT cast(string_agg('"' || replace(Name, '"', '""') || '"', ',') as string) FROM SYS.Columns WHERE SchemaName = loadMatView.schemaName  AND TableName = loadMatView.viewName);
    		VARIABLES.loadScript = 'INSERT INTO ' || matViewStageTable || '(' || columns ||') SELECT '|| columns ||' FROM ' || schemaName || '.' || viewName || ' OPTION NOCACHE ' || schemaName || '.' || viewName;
    		VARIABLES.implicitLoadScript = true;
    	END
    	
    	IF (VARIABLES.beforeLoadScript IS NOT null)
    	BEGIN
    	   VARIABLES.index = 1;
    	   declare string[] strings = tokenize(VARIABLES.beforeLoadScript, ';');
    	   VARIABLES.lineCount = array_length(strings);
    	    WHILE (index <= lineCount)
    	    BEGIN 
        	   EXECUTE IMMEDIATE array_get(strings, index);
        	   index = index +1;
        	END
        END

        VARIABLES.index = 1;
        declare string[] strings = tokenize(VARIABLES.loadScript, ';');
        VARIABLES.lineCount = array_length(strings);
        WHILE (index <= lineCount)
        BEGIN 
           EXECUTE IMMEDIATE array_get(strings, index);
           index = index +1;
        END        
        
        IF (VARIABLES.implicitLoadScript)
        BEGIN
	       rowsUpdated = VARIABLES.rowcount;
        END 
        ELSE
        BEGIN
	       EXECUTE IMMEDIATE 'SELECT count(*) as rowCount FROM ' || targetSchemaName || '.' || matViewTable AS rowCount integer INTO #load_count;        
           rowsUpdated = (SELECT rowCount FROM #load_count);        
        END 
    	
    	IF (VARIABLES.afterLoadScript IS NOT null)
    	BEGIN
            VARIABLES.index = 1;
            strings = tokenize(VARIABLES.afterLoadScript, ';');
            VARIABLES.lineCount = array_length(strings);
            WHILE (index <= lineCount)
            BEGIN 
               EXECUTE IMMEDIATE array_get(strings, index);
               index = index +1;
            END        
        END
        
        EXECUTE IMMEDIATE updateStmt || ' AND loadNumber = DVARS.loadNumber' USING  loadNumber = VARIABLES.loadNumber, vdbName = VARIABLES.vdbName, vdbVersion = VARIABLES.vdbVersion, schemaName = schemaName, viewName = loadMatView.viewName, updated = now(), LoadState = 'LOADED', valid = true, cardinality = VARIABLES.rowsUpdated;        			
        VARIABLES.status = 'DONE';
    EXCEPTION e 
        EXECUTE IMMEDIATE updateStmt || ' AND loadNumber = DVARS.loadNumber' USING  loadNumber = VARIABLES.loadNumber, vdbName = VARIABLES.vdbName, vdbVersion = VARIABLES.vdbVersion, schemaName = schemaName, viewName = loadMatView.viewName, updated = now(), LoadState = 'FAILED_LOAD', valid = VARIABLES.valid AND NOT invalidate, cardinality = -1;
        VARIABLES.status = 'FAILED';
        VARIABLES.rowsUpdated = -3;
        EXECUTE logMsg(context=>'org.teiid.MATVIEWS', level=>'WARN', msg=>e.exception);
    END

	RETURN  rowsUpdated;
END


CREATE VIRTUAL PROCEDURE updateMatView(IN schemaName string NOT NULL, IN viewName string NOT NULL, IN refreshCriteria string) RETURNS integer
AS
BEGIN
	DECLARE string vdbName = (SELECT Name FROM VirtualDatabases);
	DECLARE integer vdbVersion = (SELECT convert(Version, integer) FROM VirtualDatabases);
	DECLARE string uid = (SELECT UID FROM Sys.Tables WHERE VDBName = VARIABLES.vdbName AND SchemaName = updateMatView.schemaName AND Name = updateMatView.viewName);
	DECLARE integer rowsUpdated = 0;
	DECLARE string crit;
	DECLARE boolean invalidate = false;
	
	IF (uid IS NULL)
	BEGIN
		RAISE SQLEXCEPTION 'The view was not found';
	END
	
	DECLARE boolean isMaterialized = (SELECT IsMaterialized FROM SYS.Tables WHERE UID = VARIABLES.uid);
	
	IF (NOT isMaterialized)
	BEGIN
		RAISE SQLEXCEPTION 'The view is not declared as Materialized View in Metadata';
	END		
	
	DECLARE string statusTable = (SELECT "value" from SYS.Properties WHERE UID = VARIABLES.uid AND Name = '{http://www.teiid.org/ext/relational/2012}MATVIEW_STATUS_TABLE');
	DECLARE string[] targets = (SELECT (TargetName, TargetSchemaName) from SYSADMIN.MatViews WHERE VDBName = VARIABLES.vdbName AND SchemaName = updateMatView.schemaName AND Name = updateMatView.viewName);
    DECLARE string matViewTable = array_get(targets, 1);
    DECLARE string targetSchemaName = array_get(targets, 2);
	DECLARE string scope = (SELECT "value" from SYS.Properties WHERE UID = VARIABLES.uid AND Name = '{http://www.teiid.org/ext/relational/2012}MATVIEW_SHARE_SCOPE');

	IF ((scope IS null) OR (scope = 'NONE'))
	BEGIN 
		VARIABLES.crit = ' WHERE VDBName = DVARS.vdbName AND VDBVersion = DVARS.vdbVersion AND schemaName = DVARS.schemaName AND Name = DVARS.viewName';
	END
	ELSE IF (scope = 'VDB')
	BEGIN
		VARIABLES.crit = ' WHERE VDBName = DVARS.vdbName AND schemaName = DVARS.schemaName AND Name = DVARS.viewName';
	END
	ELSE IF (scope = 'SCHEMA')
	BEGIN
		VARIABLES.crit = ' WHERE schemaName = DVARS.schemaName AND Name = DVARS.viewName';
	END
	
	DECLARE string updateStmtWithCardinality = 'UPDATE ' || VARIABLES.statusTable || ' SET LoadState = DVARS.LoadState, valid = DVARS.valid, Updated = DVARS.updated, Cardinality = DVARS.cardinality' ||  crit;

    BEGIN ATOMIC
        DECLARE string columns = (SELECT cast(string_agg('"' || replace(Name, '"', '""') || '"', ',') as string) FROM SYS.Columns WHERE SchemaName = updateMatView.schemaName  AND TableName = updateMatView.viewName);
        EXECUTE IMMEDIATE 'DELETE FROM '|| targetSchemaName || '.' || matViewTable || ' WHERE ' ||  refreshCriteria AS rowCount integer;
        EXECUTE IMMEDIATE 'INSERT INTO ' || targetSchemaName || '.' || matViewTable || ' (' || columns || ') SELECT '|| columns ||' FROM '|| schemaName || '.' || viewName || ' WHERE ' || refreshCriteria || ' OPTION NOCACHE ' || schemaName || '.' || viewName;
    	
        EXECUTE IMMEDIATE 'SELECT count(*) as rowCount FROM ' || targetSchemaName || '.' || matViewTable AS rowCount integer INTO #load_count;        
        rowsUpdated = (SELECT rowCount FROM #load_count);        
        EXECUTE IMMEDIATE updateStmtWithCardinality USING vdbName = VARIABLES.vdbName, vdbVersion = VARIABLES.vdbVersion, schemaName = schemaName, viewName = updateMatView.viewName, updated = now(), LoadState = 'LOADED', valid = true, cardinality = VARIABLES.rowsUpdated;        			
    EXCEPTION e 
        VARIABLES.rowsUpdated = -3;
        EXECUTE logMsg(context=>'org.teiid.MATVIEWS', level=>'WARN', msg=>e.exception);
    END

	RETURN  rowsUpdated;
END