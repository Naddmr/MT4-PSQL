unit uMT4_PQ_WriterClass;

{$mode objfpc}{$H+}

interface

uses
	cMem,
        Classes,
        Windows,
        SysUtils,
        DateUtils,
        uPQWriterDefinitions,
        sqldb,
        pqconnection;

type
MT4PQWriterClass = Class
private
        config				: PQConfigClass;
	isConnected			: Boolean;
	DBConnection			: TPQConnection;
	DBTransaction			: TSQLTransaction;
	insertTickQuery			: TSQLQuery;
public
	constructor Create(
        	pConfig			: PQConfigClass
	);
	destructor Destroy(); override;
	//
	function writeTick(
		pSQLTick		: pSQLTickRow;
		pRetryCounter		: DWORD
	) : boolean;
private
        // log a message to the debug monitor
	procedure Log(AMessage: WideString);
	procedure Log(AMessage: WideString; AArgs: array of const);

end;

implementation

constructor MT4PQWriterClass.Create(pConfig			: PQConfigClass);
begin
        self.log('tMT4PQWriterClass.create: Invoking create...');
        config:=pConfig;
        try
	        isConnected:=false;
        	self.log('MT4PQWriterClass.create: Connecting...');
	     	DBConnection:=TPQConnection.create(NIL);
        	self.log('MT4PQWriterClass.create: Created ...');
	     	DBConnection.HostName:=config.DBHostname;
		self.log('MT4PQWriterClass.create: HostName="%s"', [DBConnection.HostName]);
	     	DBConnection.DatabaseName:=config.DBName;
        	self.log('MT4PQWriterClass.create: DatabaseName="%s"', [DBConnection.DatabaseName]);
	     	DBConnection.UserName:=config.DBUsername;
        	self.log('MT4PQWriterClass.create: UserName="%s"', [DBConnection.UserName]);
	     	DBConnection.Password:=config.DBPassword;
        	self.log('MT4PQWriterClass.create: Password="%s"', [DBConnection.Password]);
	        DBConnection.Params.Add('port='+IntToStr(config.DBHostPort));
        	self.log('MT4PQWriterClass.create: Parameters set ... connecting ...');
	     	DBConnection.Open;
                DBTransaction := TSQLTransaction.Create(NIL);
  		DBTransaction.Database := DBConnection;
                log('MT4PQWriterClass.create: Connection successful - exiting');
                // A Query to insert a tick into SQL
                log('PQWriterClass.create: Creating tick insert-query');
                insertTickQuery:=TSQLQuery.create(NIL);
                insertTickQuery.DataBase:=DBConnection;
                insertTickQuery.SQL.Text:='insert into t_mt4_ticks (pair_id, loctimestamp, tick_cnt, ttimestamp, isBadTick, dbid, dask, dlast, dvolume) values ' +
                			'(:PAIRID, cast(:LOCTIMESTAMP as timestamptz), :TICKCOUNTER, cast(:TIMESTAMP as timestamptz), :ISROQUETICK, :BID, :ASK, :LAST, :VOLUME)';
                			// Using this the time zone information gets lost.
                                        // '(:PAIRID, :TIMESTAMP, :BID, :ASK, :LAST, :VOLUME)';
                isConnected:=true;
        except on E:Exception do begin
                	Log('MT4PQWriterClass.create: Error "%s"', [E.Message]);
                        isConnected:=false;
		end;
	end;
end;

destructor MT4PQWriterClass.Destroy();
begin
        isConnected:=false;

        log('MT4PQWriterClass.destroy: Destroying ...');
        insertTickQuery.free;
     	//
        log('MT4PQWriterClass.destroy: Disconnecting ...');
        try
                DBTransaction.Rollback;
                DBTransaction.Free;
        	DBConnection.Close;
                DBConnection.Free;
	except on E:Exception do begin
        		Log('PQWriterClass.destroy: Error "%s"', [E.Message]);
		end;
       	end;
        isConnected:=false;
        log('MT4PQWriterClass.DBDisconnect: Disconnected...');
        inherited destroy;
end;

function MT4PQWriterClass.writeTick(
  	pSQLTick		: pSQLTickRow;
        pRetryCounter		: DWORD
) : boolean;
var
          isRoqueTick			: boolean;
          localTime			: TDateTime;
begin
     	if (not isConnected) then begin
        	log('MT4PQWriterClass.writeTick: Not connected ...');
        	exit(false);
	end;
        if (pRetryCounter>=config.MaxRetries) then begin
        	log('MT4PQWriterClass.writeTick:  Max. retries reached "%d"', [pRetryCounter]);
                exit(false);
        end;
        isRoqueTick:=false;
        pSQLTick^.TickCounter:=pSQLTick^.TickCounter+pRetryCounter;
        localTime:=TimeStampToDateTime(pSQLTIck^.localTime);
        //log('MT4PQWriterClass.writeTick:       DBW pair_id=%d, broker_tz=%s, tts=%d, bid=%.5f, ask=%.5f',
        //		[pSQLTick^.pairID, pSQLTick^.BrokerTimeZone, pSQLTick^.MQLTick.time, pSQLTick^.MQLTick.bid, pSQLTick^.MQLTick.ask]
        //	);
	try
                // Primary key
                insertTickQuery.Params.ParamByName('PAIRID').AsInteger:=pSQLTick^.pairID;
                insertTickQuery.Params.ParamByName('LOCTIMESTAMP').AsString:=FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', localTime) + ' ' + config.ThisMachineTimezone;
                insertTickQuery.Params.ParamByName('TICKCOUNTER').AsInteger:=pSQLTick^.TickCounter;
                // Payload
                insertTickQuery.Params.ParamByName('TIMESTAMP').AsString:=FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', pSQLTick^.TickTime) + ' ' + pSQLTick^.BrokerTimeZone;
                insertTickQuery.Params.ParamByName('ISROQUETICK').AsBoolean:=isRoqueTick;
                insertTickQuery.Params.ParamByName('BID').AsFloat:=pSQLTick^.MQLTick.bid;
                insertTickQuery.Params.ParamByName('ASK').AsFloat:=pSQLTick^.MQLTick.ask;
                insertTickQuery.Params.ParamByName('LAST').AsFloat:=pSQLTick^.MQLTick.last;
                insertTickQuery.Params.ParamByName('VOLUME').AsLargeInt:=pSQLTick^.MQLTick.volume;
                // log('MT4PQWriterClass.writeTick: Commencing ExecSQL ');
                insertTickQuery.ExecSQL;
                // log('PQWriterClass.writeTick: Commencing Commit ');
                DBTransaction.Commit;
                insertTickQuery.Close;
        except
          	on E:Exception do begin
                	log('MT4PQWriterClass.writeTick: DBError "%s", trace="%s"', [E.Message, config.StackTrace(E)]);
                        log('MT4PQWriterClass.writeTick: DBError pRetry=%d',
                        	[pRetryCounter]
                        );
                        if (DBConnection.Connected) then begin
                        	DBTransaction.Rollback;
                                log('MT4PQWriterClass.writeTick: DBError but still connected - retry %d', [pRetryCounter]);
        	                exit( writeTick(pSQLTick, pRetryCounter+1) );
                        end else begin
				log('MT4PQWriterClass.writeTick: DBError - not connected - discarding tick!');
                                cmem.Free(pSQLTick);
                                exit(false);
			end;
		end;
	end;
        cmem.Free(pSQLTick);
        exit(true);
end;

// log a message to the debug monitor
procedure MT4PQWriterClass.Log(AMessage: WideString);
begin
	OutputDebugStringW( PWideChar(AMessage) );
end;

// log a formatted message to the debug monitor
procedure MT4PQWriterClass.Log(AMessage: WideString; AArgs: array of const);
begin
	Log(Format(AMessage, AArgs));
end;

end.

