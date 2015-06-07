unit umt4_PQ_QueueManager;


{$mode objfpc}{$H+}

interface

uses
	cMem,
  	Windows,
	Classes,
	SysUtils,
	// FileUtil,
	// Forms,
	// Controls,
	// Graphics,
	// Dialogs,
	// StdCtrls,
        dateutils,
        sqldb,
        pqconnection,
	uPQWriterDefinitions,
        umt4_pq_writerwindow;


type
tPairInfoRec = Record
        PairID		: Integer;
        BrokerID	: Integer;
	PairName	: AnsiString;
        LastTimestamp	: Comp;
        TickCounter	: DWORD;

end;
pPairInfoRec = ^tPairInfoRec;
//
PairInfoListClass = class(TFPList)
        constructor create();
        destructor destroy(); override;
        function SeekByID(pPairID	: Integer) : pPairInfoRec;
        function SeekByName(pPairName	: AnsiString) : pPairInfoRec;
        procedure add(pPairInfo	: pPairInfoRec);
        procedure add(  pPairID		: Integer;
                	pBrokerID	: Integer;
                	pPairName	: AnsiString);

end;
//
MT4PQueueManagerClass = class (TThread)
protected
        MaxQueueLength			: QWORD;
        InTickQueue			: TFPList;
        //
	OutTickQueue			: TFPList;
        PairInfoList			: PairInfoListClass;
        ThisThreadList			: TFPList;
        parent				: TfrmWriterWindow;
        BrokerSHMObj			: PQShareMemClass;
        PairSHMObj			: PQShareMemClass;
	TickSHMObj			: PQShareMemClass;
        // Database connection and Transaction
        DBConnection			: TPQConnection;
	DBTransaction			: TSQLTransaction;
        isConnected			: Boolean;
        isInitalized			: Boolean;
        isStopping			: Boolean;
        isStopped			: Boolean;
        // SQL Broker management
	getBrokerIDQuery		: TSQLQuery;
        getAllBrokersQuery		: TSQLQuery;
	insertBrokerIDQuery		: TSQLQuery;
	// SQL Pair management
	getPairQuery			: TSQLQuery;
        getAllPairsQuery		: TSQLQuery;
	insertPairQuery			: TSQLQuery;
	// SQL Aliasmanagement
	getAliasQuery			: TSQLQuery;
	insertAliasQuery		: TSQLQuery;
        getAliasPairQuery		: TSQLQuery;
	insertAliasPairQuery		: TSQLQuery;

public
        config				: PQConfigClass;
        OutQueueCriticalSection		: TRTLCriticalSection;
        TicksWritten			: DWORD64;
        constructor create(
        	pParent			: TfrmWriterWindow
        );
        destructor destroy(); override;
        procedure Execute(); override;
        procedure RegisterBroker();
	procedure RegisterPair();
	procedure HandleTick();

        procedure pushTick(pSQLTick	: pSQLTickRow);
	function PopTick() 		: pSQLTickRow;
        function OutQueueLength()	: Integer;

private
        // log a message to the debug monitor
	procedure Log(AMessage: WideString);
	procedure Log(AMessage: WideString; AArgs: array of const);
        procedure getAllBrokerData();
        procedure getAllPairData();
        procedure getAliasData(pPairID	: Integer; pPairName	: AnsiString; pBrokerID	: Integer);
end;


implementation
uses
        uMT4_PQ_ThreadClass;
constructor PairInfoListClass.create();
begin
        inherited create();
end;

destructor PairInfoListClass.destroy();
begin
	while (Count>0) do begin
        	Dispose(pPairInfoRec(Items[0]));
                Delete(0);
	end;
	inherited destroy();
end;

procedure PairInfoListClass.add(pPairInfo	: pPairInfoRec);
begin
	inherited add(pPairInfo);
end;

procedure PairInfoListClass.add(  pPairID		: Integer;
        	pBrokerID	: Integer;
        	pPairName	: AnsiString);
var
        p	: pPairInfoRec;
begin
	p:=new(pPairInfoRec);
        p^.BrokerID:=pBrokerID;
        p^.PairID:=pPairID;
        p^.PairName:=pPairName;
        p^.LastTimestamp:=0;
        p^.TickCounter:=0;
        self.add(p);
end;

function PairInfoListClass.SeekByID(pPairID	: Integer) : pPairInfoRec;
var
        i	: Integer;
        found	: Boolean;
        rc	: pPairInfoRec;
begin
        i:=0;
        found:=false;
        while (i<Count) and (not found) do begin
        	rc:=Items[i];
                found:=(rc^.PairID=pPairID);
                inc(i);
	end;
        if (not found) then begin
                rc:=NIL;
	end;
        exit(rc);
end;

function PairInfoListClass.SeekByName(pPairName: AnsiString) : pPairInfoRec;
var
        i	: Integer;
        found	: Boolean;
        rc	: pPairInfoRec;
begin
        i:=0;
        found:=false;
        while (i<Count) and (not found) do begin
        	rc:=Items[i];
                found:=(rc^.PairName=pPairName);
	end;
        if (not found) then begin
                rc:=NIL;
	end;
        exit(rc);
end;

constructor MT4PQueueManagerClass.create(pParent : TfrmWriterWindow);
var
        i		: DWORD;
begin
        self.parent:=pParent;
        self.config:=parent.Config;
        self.log('MT4PQueueManagerClass.create: Invoking...');
        //
        TicksWritten:=0;
        MaxQueueLength:=0;
 	InitializeCriticalSection(OutQueueCriticalSection);
        OutTickQueue:=TFPList.Create();
        PairInfoList:=PairInfoListClass.Create();
        // Create shared memory handles and
        // Mutexes for synchronous access
        BrokerSHMObj:=PQShareMemClass.create(config.BrokerShareMemName, Sizeof(TSQLBrokerRow), config.MaxBrokers);
        PairSHMObj:=PQShareMemClass.create(config.PairShareMemName, Sizeof(TSQLPairRow), config.MaxBrokers * config.MaxCharts);
        TickSHMObj:=PQShareMemClass.create(config.TickShareMemName, Sizeof(TSQLTickRow), config.MaxBrokers * config.MaxCharts * config.MaxTicks);
        //
        // Initialize Broker and Pairdata in the shared memory regions
        isConnected:=false;
        isStopping:=false;
        isStopped:=false;
        log('MT4PQueueManagerClass.create: Connecting...');
     	DBConnection:=TPQConnection.create(NIL);
        log('MT4PQueueManagerClass.create: Created ...');
     	DBConnection.HostName:=config.DBHostname;
	log('MT4PQueueManagerClass.create: HostName="%s"', [DBConnection.HostName]);
     	DBConnection.DatabaseName:=config.DBName;
        log('MT4PQueueManagerClass.create: DatabaseName="%s"', [DBConnection.DatabaseName]);
     	DBConnection.UserName:=config.DBUsername;
        log('MT4PQueueManagerClass.create: UserName="%s"', [DBConnection.UserName]);
     	DBConnection.Password:=config.DBPassword;
        log('MT4PQueueManagerClass.create: Password="%s"', [DBConnection.Password]);
        DBConnection.Params.Add('port='+IntToStr(config.DBHostPort));
        log('MT4PQueueManagerClass.create: Parameters set ... connecting ...');
        try
	     	DBConnection.Open;
                DBTransaction := TSQLTransaction.Create(NIL);
  		DBTransaction.Database := DBConnection;
                log('MT4PQueueManagerClass.create: Connection successful - exiting');
                // A Query to get the broker id into ThisBrokerID;
                getBrokerIDQuery:=TSQLQuery.create(NIL);
                getBrokerIDQuery.DataBase:=DBConnection;
                getBrokerIDQuery.SQL.Text:='select * from t_mt4_brokers where ' +
                		'brokername=:BROKERNAME and broker_timezone=:BROKERTIMEZONE and is_demo=:ACCOUNTISDEMO';
                // A Query to fetch all brokers into SHM
                getAllBrokersQuery:=TSQLQuery.create(NIL);
                getAllBrokersQuery.DataBase:=DBConnection;
                getAllBrokersQuery.SQL.Text:='select * from t_mt4_brokers';

                // A Query to insert a new broker into SQL
                insertBrokerIDQuery:=TSQLQuery.create(NIL);
                insertBrokerIDQuery.DataBase:=DBConnection;
                insertBrokerIDQuery.SQL.Text:='insert into t_mt4_brokers (brokername, broker_timezone, is_demo) values (:BROKERNAME, :BROKERTIMEZONE, :ACCOUNTISDEMO)';

                // A Query to get the Symbolid into ThisPairID;
                getPairQuery:=TSQLQuery.create(NIL);
                getPairQuery.DataBase:=DBConnection;
                getPairQuery.SQL.Text:='select * from t_mt4_pairdata where pairname=:THISPAIRNAME and broker_id=:BROKERID';

                // A Query to get all pairs into SHM
                getAllPairsQuery:=TSQLQuery.create(NIL);
                getAllPairsQuery.DataBase:=DBConnection;
                getAllPairsQuery.SQL.Text:='select * from t_mt4_pairdata';

                // A Query to insert a new pair into SQL
                insertPairQuery:=TSQLQuery.create(NIL);
                insertPairQuery.DataBase:=DBConnection;
                insertPairQuery.SQL.Text:='insert into t_mt4_pairdata (broker_id, pairname, point, digits) values ' +
                				'(:BROKERID, :THISPAIRNAME, :THISPOINT, :THISDIGITS)';

                // A Query to get the alias name ID into ThisPairAliasID
                getAliasQuery:=TSQLQuery.create(NIL);
                getAliasQuery.DataBase:=DBConnection;
                getAliasQuery.SQL.Text:='select * from t_mt4_aliasnames a where a.pairname=:THISPAIRNAME';

                // A Query to insert a new alias name into SQL
                insertAliasQuery:=TSQLQuery.create(NIL);
                insertAliasQuery.DataBase:=DBConnection;
                insertAliasQuery.SQL.Text:='insert into t_mt4_aliasnames (pairname) values (:THISPAIRNAME)';

                // A Query to get the alias name ID into ThisPairAliasID using a name and a broker id
                getAliasPairQuery:=TSQLQuery.create(NIL);
                getAliasPairQuery.DataBase:=DBConnection;
                getAliasPairQuery.SQL.Text:='select *, a.pairname as aliasname from t_mt4_pairdata p ' +
                	' join t_mt4_pairaliases pa using (pair_id) ' +
                        ' join t_mt4_aliasnames a using (alias_id) ' +
                        ' join t_mt4_brokers b using (broker_id) ' +
                        ' where p.pairname=:THISPAIRNAME and b.broker_id=:BROKERID';

                // A Query to insert a new alias-pair relation into SQL
                insertAliasPairQuery:=TSQLQuery.create(NIL);
                insertAliasPairQuery.DataBase:=DBConnection;
                insertAliasPairQuery.SQL.Text:='insert into t_mt4_pairaliases (pair_id, alias_id) values (:THISPAIRID, :THISALIASID)';
                getAllBrokerData();
                getAllPairData();
                isConnected:=true;
                isInitalized:=true;
        except on E:Exception do begin
                	Log('MT4PQueueManagerClass.create: Error "%s"', [E.Message]);
                        isConnected:=false;
                        isInitalized:=false;
		end;
	end;
        //
        // Create Database writer threads after the Broker and Pair data are current
        //
        ThisThreadList:=TFPList.Create();
        for i:=1 to Config.DBThreadCount do begin
		ThisThreadList.Add(MT4PQWriterThreadClass.Create(self));
	end;
        inherited create(false);
        self.log('MT4PQueueManagerClass.Create: Starting ...');
        self.start();
        self.Resume();
        self.log('MT4PQueueManagerClass.Create: Done ...');
        //
        // TODO: Signal preparedness state to other processes
        //
end;

destructor MT4PQueueManagerClass.destroy();
var
        i	: DWORD;
        t	: MT4PQWriterThreadClass;
begin
        self.log('MT4PQueueManagerClass.destroy: Invoking ...');
        isStopping:=true;
        log('MT4PQueueManagerClass.Destroy: Terminating SQL writer threads ...');
        while (ThisThreadList.Count>0) do begin
                t:=MT4PQWriterThreadClass(ThisThreadList.Items[0]);
        	FreeAndNIL( t );
                ThisThreadList.Delete(0);
	end;
        log('MT4PQueueManagerClass.Destroy: Stopping Queuemanager thread ...');
        i:=1;
        while (not isStopped) and (i<=config.MaxRetries) do begin
		// Awake the thread loop again to get it dead :)
                self.Resume();
                sleep(config.PollingInterval);
                log('MT4PQueueManagerClass.Destroy: Waiting ...');
                inc(i);
	end;
        if (i>=config.MaxRetries) then begin
        	log('MT4PQueueManagerClass.Destroy: Timeout - stopping immediately...');
                self.Terminate;
	end;

	OutTickQueue.Destroy();
        PairInfoList.destroy();
        ThisThreadList.Destroy();
        DeleteCriticalSection(OutQueueCriticalSection);
        FreeAndNil(BrokerSHMObj);
        FreeAndNil(PairSHMObj);
        FreeAndNil(TickSHMObj);

        getBrokerIDQuery.free;
        getAllBrokersQuery.free;
        insertBrokerIDQuery.free;
        getPairQuery.free;
        getAllPairsQuery.free;
        insertPairQuery.free;
        self.log('MT4PQueueManagerClass.destroy: Disconnecting ...');
        try
                DBTransaction.Rollback;
                DBTransaction.Free;
        	DBConnection.Close;
                DBConnection.Free;
	except on E:Exception do begin
        		Log('MT4PQueueManagerClass.destroy: Error "%s"', [E.Message]);
		end;
       	end;
        isConnected:=false;
        self.log('MT4PQueueManagerClass.destroy: Done ...');
        inherited destroy;
end;

procedure MT4PQueueManagerClass.Execute();
var
        bp			: pFifoRecord;
        cp			: pFIFORecord;
        tp			: pFIFORecord;
        RefreshDisplayTimer	: TDateTime;
var
        c		: QWORD;
begin
        log('MT4PQueueManagerClass.Execute: Starting queue manager loop ...');
        bp:=BrokerSHMObj.FiFoPtr;
        cp:=PairSHMObj.FiFoPtr;
        tp:=TickSHMObj.FiFoPtr;
        RefreshDisplayTimer:=now;
        c:=0;
        while (not isStopping) do begin
		if (SecondsBetween(RefreshDisplayTimer, now)>1) then begin
                	parent.labTicksWrittenDisplay.Caption:=Format('%d', [TicksWritten]);
                        TicksWritten:=0;
                        RefreshDisplayTimer:=now;
		end;
		// Check signal state
                // 	- New broker introduced
                while (bp^.write_idx<>bp^.read_idx) and (not isStopping) do begin
                       	// call new broker registration
                        RegisterBroker();
		end;
		// 	- New chart introduced
                while (cp^.write_idx<>cp^.read_idx) and (not isStopping)  do begin
                        // call new pair registration
                        RegisterPair();
                end;
		// 	- New Ticks received
                while (tp^.write_idx<>tp^.read_idx) and (not isStopping)  do begin
                        // Push new ticks to the output queue
                        HandleTick();
                end;
                c:=OutTickQueue.Count;
                parent.labQueueLengthDisplay.Caption:=Format('%d', [c]);
                if (c>self.MaxQueueLength) then begin
                	self.MaxQueueLength:=c;
                	parent.labMaxCurrentQueueLengthDisplay.Caption:=Format('(max. %d)', [self.MaxQueueLength]);
		end;
		Sleep(config.PollingInterval);
	end;
        log('MT4PQueueManagerClass.Execute: Terminated ...');
        isStopped:=true;
end;

procedure MT4PQueueManagerClass.RegisterBroker();
var
        BrokerID	: Integer;
        BrokerName	: AnsiString;
        BrokerTimeZone	: AnsiString;
        Broker_Is_Demo	: Boolean;
        fp		: pFIFORecord;
        bp		: pSQLBrokerRow;
begin
       	Log('MT4PQueueManagerClass.RegisterBroker: Invoking ... ');
	try
                BrokerSHMObj.Lock();
                try
			fp:=BrokerSHMObj.FiFoPtr;
		        // bp:=Pointer(fp)+SizeOf(TFiFoRecord) + fp^.read_idx*SizeOf(TSQLBrokerRow);
                        bp:=BrokerSHMObj.RowPtr;
                        inc(bp,fp^.read_idx);
        		BrokerName:=bp^.broker_name;
		        BrokerTimeZone:=bp^.broker_timezone;
	        	Broker_Is_Demo:=bp^.is_demo;
		        BrokerID:=bp^.broker_id;
	        	if (BrokerID<>0) then begin
	        	        // Broker is already registered
        	        	inc(fp^.read_idx);
                                // the finally block will handle the IPC unlock
	        	        exit;
			end;
			getBrokerIDQuery.Params.ParamByName('BROKERNAME').AsString:=BrokerName;
			getBrokerIDQuery.Params.ParamByName('BROKERTIMEZONE').AsString:=BrokerTimeZone;
			getBrokerIDQuery.Params.ParamByName('ACCOUNTISDEMO').AsBoolean:=Broker_Is_Demo;
			Log('MT4PQueueManagerClass.RegisterBroker: Opening query');
		        getBrokerIDQuery.Open;
			Log('MT4PQueueManagerClass.RegisterBroker: Query opened');
			if (getBrokerIDQuery.EOF) then begin
				// create a new broker row ...
				Log('MT4PQueueManagerClass.RegisterBroker: Broker "%s" does not exist - creating ...', [bp^.broker_name]);
				getBrokerIDQuery.close;
				insertBrokerIDQuery.Params.ParamByName('BROKERNAME').AsString:=BrokerName;
				insertBrokerIDQuery.Params.ParamByName('BROKERTIMEZONE').AsString:=BrokerTimeZone;
				insertBrokerIDQuery.Params.ParamByName('ACCOUNTISDEMO').AsBoolean:=Broker_Is_Demo;
				insertBrokerIDQuery.ExecSQL;
        	               	DBTransaction.Commit;
	                        insertBrokerIDQuery.Close;
        	               	getBrokerIDQuery.Params.ParamByName('BROKERNAME').AsString:=BrokerName;
				getBrokerIDQuery.Params.ParamByName('BROKERTIMEZONE').AsString:=BrokerTimeZone;
				getBrokerIDQuery.Params.ParamByName('ACCOUNTISDEMO').AsBoolean:=Broker_Is_Demo;
        	                getBrokerIDQuery.Open;
			end;
	        	bp^.broker_id:=getBrokerIDQuery.FieldByName('broker_id').AsInteger;
        	        Log('MT4PQueueManagerClass.RegisterBroker: Fetched broker_id=%d for Broker="%s"', [bp^.broker_id, bp^.broker_name]);
                        inc(fp^.read_idx);
                        parent.labCurrBrokerCountDisplay.Caption:=Format('(curr. %d)', [fp^.read_idx-1]);
		except on E:Exception do begin
				log('MT4PQueueManagerClass.RegisterBroker: DBError "%s"', [E.Message]);
                	end;
        	end;
        finally
                // IPC Unlock!
                if (getBrokerIDQuery.Active) then
                        getBrokerIDQuery.Close;
                if (insertBrokerIDQuery.Active) then
                	insertBrokerIDQuery.Close;
                BrokerSHMObj.UnLock();
	end;

end;

procedure MT4PQueueManagerClass.RegisterPair();
var
        BrokerID	: Integer;
        PairID		: Integer;
        PairName	: AnsiString;
        Point		: Double;
        Digits		: Double;
        fp		: pFIFORecord;
        pp		: pSQLPairRow;
        isCreated	: Boolean;
begin
	Log('MT4PQueueManagerClass.RegisterPair: Invoking ... ');
        isCreated:=false;
        try
                PairSHMObj.Lock();
                try
		        fp:=PairSHMObj.FiFoPtr;
	                // pp:=Pointer(fp)+SizeOf(TFiFoRecord) + fp^.read_idx*SizeOf(TSQLPairRow);
                        pp := PairSHMObj.RowPtr;
                        inc(pp, fp^.read_idx);
	                PairID:=pp^.pair_id;
	                BrokerID:=pp^.broker_id;
	                PairName:=pp^.pair_name;
	                Point:=pp^.point;
	                Digits:=pp^.Digits;
	                if (PairID<>0) then begin
	                        // Pair is already registered...
                                inc(fp^.read_idx);;
	                        // IPC Unlock is done in the finally part
	                        exit;
		        end;
	                getPairQuery.Params.ParamByName('THISPAIRNAME').AsString:=PairName;
	                getPairQuery.Params.ParamByName('BROKERID').AsInteger:=BrokerID;
	                Log('MT4PQueueManagerClass.RegisterPair %s: Opening query ...', [PairName]);
	                try
	        	        getPairQuery.Open;
		        except on E:Exception do begin
	                	        log('PQWriterClass.RegisterPair %s: Open DBError "%s"', [PairName, E.Message]);
	                        end;
		        end;
	                Log('MT4PQueueManagerClass.RegisterPair: Query opened - fetching results ... ');
		        if (getPairQuery.EOF) then begin
	                        Log('MT4PQueueManagerClass.RegisterPair %s: Pair/broker_id("%s", %d) does not exist - creating ...', [PairName, PairName, BrokerID]);
	                        getPairQuery.close;
                                insertPairQuery.Params.ParamByName('THISPAIRNAME').AsString:=PairName;
                                insertPairQuery.Params.ParamByName('BROKERID').AsInteger:=BrokerID;
                                insertPairQuery.Params.ParamByName('THISPOINT').AsFloat:=Point;
                                insertPairQuery.Params.ParamByName('THISDIGITS').AsFloat:=Digits;
                                insertPairQuery.ExecSQL;
                                DBTransaction.Commit;
			        getPairQuery.Params.ParamByName('THISPAIRNAME').AsString:=PairName;
			        getPairQuery.Params.ParamByName('BROKERID').AsInteger:=BrokerID;
                                getPairQuery.Open;
                                isCreated:=true;
	                end;
        	        pp^.pair_id:=getPairQuery.FieldByName('pair_id').AsInteger;
                        PairInfoList.add(pp^.pair_id, pp^.broker_id, pp^.pair_name);
                        inc(fp^.read_idx);
                        parent.labCurrChartCountDisplay.Caption:=Format('(max. %d, curr. %d)', [config.MaxBrokers*config.MaxCharts, fp^.read_idx-1]);
	                Log('MT4PQueueManagerClass.RegisterPair %s: Fetched pair_id=%d for pair/broker_id("%s", %d)', [PairName, pp^.pair_id, pp^.pair_name, BrokerID]);
                        if (isCreated) then begin
                                self.getAliasData(pp^.pair_id, pp^.pair_name, pp^.broker_id);
			end;
		except on E:Exception do begin
			log('MT4PQueueManagerClass.RegisterPair %s: Insert DBError "%s"', [PairName, E.Message]);
	                end;
		end;
	finally
                if insertPairQuery.Active then
                        insertPairQuery.Close;
                if getPairQuery.Active then
                        getPairQuery.Close;
                PairSHMObj.UnLock();
	end;
end;

procedure MT4PQueueManagerClass.getAliasData(pPairID	: Integer; pPairName	: AnsiString; pBrokerID	: Integer);
var
        AliasID		: Integer;
begin
        // Locking is done in the caller! No need to take a mutex here.
        // This is because the pair creation always involves an alias
        // check and the alias check is called by pair creation only.
        // The pair creation has a try-finally check to ensure mutex release.
	Log('MT4PQueueManagerClass.getAliasData %s: Invoking for Pairname="%s" - broker_id=%d', [pPairName, pPairName, pBrokerID]);
        // This checks for a complete Alias-Pair relation
	getAliasPairQuery.Params.ParamByName('THISPAIRNAME').AsString:=pPairName;
        getAliasPairQuery.Params.ParamByName('BROKERID').AsInteger:=pBrokerID;
        Log('MT4PQueueManagerClass.getAliasData %s: Opening Alias-Pair query', [pPairName]);
        try
        	getAliasPairQuery.Open;
	except on E:Exception do begin
                	log('MT4PQueueManagerClass.getAliasData %s: Open DBError "%s"', [pPairName, E.Message]);
                end;
	end;
        Log('MT4PQueueManagerClass.getAliasData %s: Query opened - fetching results ... ', [pPairName]);
	// The AliasPairQuery produces exactly 0 or 1 result
	if (getAliasPairQuery.EOF) then begin
        	getAliasPairQuery.Close;
                // Check whether we have to insert a new Alias
                // or a new alias-pair relation
                getAliasQuery.Params.ParamByName('THISPAIRNAME').AsString:=pPairName;
                Log('MT4PQueueManagerClass.getAliasData %s: Opening Alias query', [pPairName]);
	        try
	        	getAliasQuery.Open;
		except on E:Exception do begin
        	        	log('PQWriterClass.getAliasData %s: Open DBError "%s"', [pPairName, E.Message]);
                                exit;
	                end;
		end;
        	Log('MT4PQueueManagerClass.getAliasData %s: Query opened - fetching results ... ', [pPairName]);
                if (getAliasQuery.EOF) then begin
                	// Alias name does not exist - create!
                        Log('MT4PQueueManagerClass.getAliasData %s: Aliasname does not exist - creating new ... ', [pPairName]);
                        try
                        	insertAliasQuery.Params.ParamByName('THISPAIRNAME').AsString:=pPairName;
	                        insertAliasQuery.ExecSQL;
        	                DBTransaction.Commit();
                	        InsertAliasQuery.Close();
                        	getAliasQuery.Close();
                                getAliasQuery.Params.ParamByName('THISPAIRNAME').AsString:=pPairName;
	                        getAliasQuery.Open;
                        except on E:Exception do begin
                        		log('MT4PQueueManagerClass.getAliasData %s: Insert DBError "%s"', [pPairName, E.Message]);
                                        insertAliasQuery.Close;
                                        exit;
				end;
			end;
		end;
                AliasID:=getAliasQuery.FieldByName('alias_id').AsInteger;
		Log('MT4PQueueManagerClass.getAliasData %s: Fetched alias_id=%d for newly created alias name ... ', [pPairName, AliasID]);
		getAliasQuery.close;
                Log('MT4PQueueManagerClass.getAliasData %s: Alias relation for Pair/broker_id("%s", %d) does not exist - creating ...', [pPairName, pPairName, pBrokerID]);
                try
                        insertAliasPairQuery.Params.ParamByName('THISPAIRID').AsInteger:=pPairID;
                        insertAliasPairQuery.Params.ParamByName('THISALIASID').AsInteger:=AliasID;
                        insertAliasPairQuery.ExecSQL;
                        DBTransaction.Commit;
                        insertAliasPairQuery.Close();
		except on E:Exception do begin
                	log('MT4PQueueManagerClass.getAliasData %s: Insert DBError "%s"', [pPairName, E.Message]);
                        insertAliasPairQuery.close;
                        exit;
                	end;
		end;
	end;
        Log('MT4PQueueManagerClass.getAliasData %s: Finished!', [pPairName]);
end;

procedure MT4PQueueManagerClass.HandleTick();
var
        SQLTick		: pSQLTickRow;
begin
	SQLTick:=TickSHMObj.GetRing();
        //log('MT4PQueueManagerClass.HandleTick: SHM pair_id=%d, broker_tz=%s, tts=%d, bid=%.5f, ask=%.5f',
        //	[SQLTick^.pairID, SQLTick^.BrokerTimeZone, SQLTick^.MQLTick.time, SQLTick^.MQLTick.bid, SQLTick^.MQLTick.ask]
        //);
	self.pushTick(SQLTick);
end;


procedure MT4PQueueManagerClass.pushTick(pSQLTick	: pSQLTickRow);
var
        p		: pPairInfoRec;
        c		: Comp;
begin
        // log('MT4PQueueManagerClass.pushTick: Invoking ...');
        try
                EnterCriticalSection(OutQueueCriticalSection);
		// Set the timestamp accordingly...
        	p:=PairInfoList.SeekByID(pSQLTick^.pairID);
        	if (p<>NIL) then begin
        		c:=TimeStampToMSecs(pSQLTick^.localTime);
                	if (c>p^.LastTimestamp) then begin
                        	p^.TickCounter:=0;
                        	p^.LastTimeStamp:=c;
			end else begin
                        	inc(p^.TickCounter);
			end;
                	pSQLTick^.TickCounter:=p^.TickCounter;
		end;
        	// Push the tick row
         	// log('MT4PQueueManagerClass.pushTick:   ADD pair_id=%d, broker_tz=%s, tts=%d, bid=%.5f, ask=%.5f',
        	//	[pSQLTick^.pairID, pSQLTick^.BrokerTimeZone, pSQLTick^.MQLTick.time, pSQLTick^.MQLTick.bid, pSQLTick^.MQLTick.ask]
        	//);
        	OutTickQueue.Add(pSQLTick);
        	// if (not isWriting) then self.resume();
	finally
		LeaveCriticalSection(OutQueueCriticalSection);
	end;
        // log('MT4PQueueManagerClass.pushTick: Exiting ql=%d ...', [OutTickQueue.Count]);
end;

function MT4PQueueManagerClass.PopTick() : pSQLTickRow;
var
  	rc	: pSQLTickRow;
begin
        // log('TfrmWriterWindow.PopTick: Invoking ...');
        EnterCriticalSection(OutQueueCriticalSection);
        try
		// Pull a tick row - return NIL when no tick available
        	rc:=NIL;
        	if (OutTickQueue.Count>0) then begin
			rc:=OutTickQueue.Items[0];
                	OutTickQueue.Delete(0);
		end;
	finally
                LeaveCriticalSection(OutQueueCriticalSection);
	end;
 //       if (rc<>NIL) then begin
 //               log('MT4PQueueManagerClass.PopTick:    POP pair_id=%d, broker_tz=%s, tts=%d, bid=%.5f, ask=%.5f',
 //       		[rc^.pairID, rc^.BrokerTimeZone, rc^.MQLTick.time, rc^.MQLTick.bid, rc^.MQLTick.ask]
 //       	);
	//end;
	// log('TfrmWriterWindow.PopTick: Exiting ...');
        exit(rc);
end;

function MT4PQueueManagerClass.OutQueueLength() : Integer;
var
        rc	: Integer;
begin
        EnterCriticalSection(OutQueueCriticalSection);
        rc:=OutTickQueue.Count;
        LeaveCriticalSection(OutQueueCriticalSection);
        exit(rc);
end;


// fetch all brokers into SHM
procedure MT4PQueueManagerClass.getAllBrokerData();
var
        p	: pSQLBrokerRow;
        q	: pFIFORecord;
begin
	self.log('tMT4PQueueManagerClass.getAllBrokerData: Invoking ...');
        q:=BrokerSHMObj.FiFoPtr;
        p:=BrokerSHMObj.RowPtr;
        try
                self.log('tMT4PQueueManagerClass.getAllBrokerData: Getting Lock ...');
                BrokerSHMObj.Lock();
                self.log('tMT4PQueueManagerClass.getAllBrokerData: Locked SHM ...');
	        try
	                self.log('tMT4PQueueManagerClass.getAllBrokerData: SHM=%p,     start=%p', [q,p]);
	                q^.read_idx:=0;
	                q^.write_idx:=0;
			getAllBrokersQuery.Open;
	                Log('tMT4PQueueManagerClass.getAllBrokerData: Query opened');
		        while (not getAllBrokersQuery.EOF) and (q^.read_idx<config.MaxBrokers) do begin
	        	        p^.broker_id:=getAllBrokersQuery.FieldByName('broker_id').AsInteger;
	                        p^.broker_name:=getAllBrokersQuery.FieldByName('brokername').AsString;
	                        p^.broker_timezone:=getAllBrokersQuery.FieldByName('broker_timezone').AsString;
	                        p^.is_demo:=getAllBrokersQuery.FieldByName('is_demo').AsBoolean;
                                if (p^.broker_name<>'DUMMY') then begin
                                	self.log('tMT4PQueueManagerClass.getAllBrokerData: id=%d, name="%s", tz="%s", demo=%d, ',
                                        	[p^.broker_id, p^.broker_name, p^.broker_timezone, DWORD(p^.is_demo) ]
					);
	        	                inc(q^.read_idx);
		                        inc(q^.write_idx);
		                        inc(p);
	                        	self.log('tMT4PQueueManagerClass.getAllBrokerData: SHM=%p, NEW start=%p',[q,p]);

                                end;
	                        getAllBrokersQuery.Next;
		        end;
	                getAllBrokersQuery.close;
	                self.log('tMT4PQueueManagerClass.getAllBrokerData: Fetched %d brokers into SHM', [q^.read_idx-1]);
                        parent.labCurrBrokerCountDisplay.Caption:=Format('(curr. %d)', [q^.read_idx-1]);
	        except
	        	on E:Exception do begin
	                	log('PQClass.getAllBrokerData: DBError "%s"', [E.Message]);
	                        isInitalized:=false;
	                end;
		end;
	finally
                BrokerSHMObj.UnLock();
	end;
end;


procedure MT4PQueueManagerClass.getAllPairData();
var
        bp	: pSQLPairRow;
        fp	: pFIFORecord;
        pi	: pPairInfoRec;
        ulimit	: DWORD;
begin
	self.log('tMT4PQueueManagerClass.getAllPairData: Invoking ...');
        try
                PairSHMObj.Lock();
                fp:=PairSHMObj.FiFoPtr;
	        bp:=PairSHMObj.RowPtr;
        	self.log('tMT4PQueueManagerClass.getAllPairData: SHM=%p,     start=%p', [fp,bp]);
                fp^.read_idx:=0;
        	fp^.write_idx:=0;
		try
	        	getAllPairsQuery.Open;
		except
        	  	on E:Exception do begin
                		log('PQClass.getAllPairData: DBError "%s"', [E.Message]);
                        	isInitalized:=false;
                	end;
		end;
	        Log('tMT4PQueueManagerClass.getAllPairData: Query opened');
	        ulimit:=config.MaxCharts*config.MaxBrokers;
		while (not getAllPairsQuery.EOF) and (fp^.read_idx<ulimit) do begin
	        	bp^.pair_id:=getAllPairsQuery.FieldByName('pair_id').AsInteger;
        	        bp^.broker_id:=getAllPairsQuery.FieldByName('broker_id').AsInteger;
                	bp^.pair_name:=getAllPairsQuery.FieldByName('pairname').AsString;
	                bp^.point:=getAllPairsQuery.FieldByName('point').AsFloat;
        	        bp^.Digits:=getAllPairsQuery.FieldByName('digits').AsFloat;
                        if (bp^.pair_name<>'DUMMY') then begin
                                self.log('tMT4PQueueManagerClass.getAllPairData: pid=%d, bid=%d, name="%s", pt=%.5f, dig=%.0f',
                                        [bp^.pair_id, bp^.broker_id, bp^.pair_name, bp^.point, bp^.Digits ]
				);
	                	inc(fp^.read_idx);
	                	inc(fp^.write_idx);
        		        pi:=new(pPairInfoRec);
        	        	pi^.PairID:=bp^.pair_id;
		                pi^.BrokerID:=bp^.broker_id;
        	        	pi^.LastTimestamp:=0;
                		pi^.PairName:=bp^.pair_name;
		                PairInfoList.add(pi);
	        	        inc(bp);
                		self.log('tMT4PQueueManagerClass.getAllPairData: SHM=%p, NEW start=%p', [fp,bp]);
                        end;
	                getAllPairsQuery.Next;
		end;
	        getAllPairsQuery.close;
        	self.log('tMT4PQueueManagerClass.getAllPairData: Fetched %d pairs into SHM', [fp^.read_idx-1]);
                parent.labCurrChartCountDisplay.Caption:=Format('(max. %d, curr. %d)', [config.MaxBrokers*config.MaxCharts, fp^.read_idx-1]);
	finally
                PairSHMObj.UnLock();
	end;
end;


// log a message to the debug monitor
procedure MT4PQueueManagerClass.Log(AMessage: WideString);
begin
	OutputDebugStringW( PWideChar(AMessage) );
end;

// log a formatted message to the debug monitor
procedure MT4PQueueManagerClass.Log(AMessage: WideString; AArgs: array of const);
begin
	Log(Format(AMessage, AArgs));
end;

end.

