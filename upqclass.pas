{
    Copyright 2015 Naddmr, http://www.forexfactory.com

    This file is part of the mt4psql project.

    mt4psql is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    mt4psql is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with mt4psql.  If not, see <http://www.gnu.org/licenses/>.
}
unit UpqClass;

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
//
PQWriterClass = class
protected
        config				: PQConfigClass;
        // Parameters ...
        PredTTimeStamp,
        CurrTTimeStamp			: TTimeStamp;
        MaxRetries			: DWORD;
        // Own variables ...
        lastTickSecond			: UINT64;
        CurrTickTime			: TDateTime;
        CurrLocTime			: TDateTime;
        PredLocTime			: TDateTime;
        TickCounter			: DWORD;
        //
        ThisBrokerID			: Integer;
        ThisPairID			: Integer;
        ThisAliasID			: Integer;
        ThisAliasName			: AnsiString;
        DBConnection			: TPQConnection;
        DBTransaction			: TSQLTransaction;
        isConnected			: boolean;
        isInitalized			: Boolean;
        insertTickQuery			: TSQLQuery;
        // SQL Broker management
        getBrokerIDQuery		: TSQLQuery;
        insertBrokerIDQuery		: TSQLQuery;
        // SQL Pair management
        getPairQuery			: TSQLQUery;
        insertPairQuery			: TSQLQuery;
        // SQL Aliasmanagement
        getAliasQuery			: TSQLQuery;
        insertAliasQuery		: TSQLQuery;
        getAliasPairQuery		: TSQLQuery;
        insertAliasPairQuery		: TSQLQuery;
        SessionSettingsQuery		: TSQLQuery;

public
	constructor create(
                pConfig			: PQConfigClass
	);
        //
	destructor Destroy(); override;
        //
        Function writeTick(
                pSQLTick		: pSQLTickRow;
                pRetryCounter		: DWORD
        ) : Boolean;
        //
        property isValid : boolean read isConnected;



private
        //
        procedure getBrokerData();
        procedure getPairData();
        procedure getAliasData();


end;

implementation

constructor PQWriterClass.create(
        pConfig			: PQConfigClass
);
begin
     	log('PQWriterClass.create %s: Invoking', [config.ThisPairName]);
        ThisBrokerID:=-1;
        ThisPairID:=-1;
        ThisAliasID:=-1;
        isInitalized:=true;
        PredLocTime:=0;
        DBTransaction:=NIL;
        DBConnection:=NIL;
        log('PQWriterClass.create %s: Connecting...', [config.ThisPairName]);
     	DBConnection:=TPQConnection.create(NIL);
        log('PQWriterClass.create %s: Created ...', [config.ThisPairName]);
     	DBConnection.HostName:=Utf8ToAnsi(config.DBHostname);
	log('PQWriterClass.create %s: HostName="%s"', [config.ThisPairName, DBConnection.HostName]);
     	DBConnection.DatabaseName:=Utf8ToAnsi(config.DBName);
        log('PQWriterClass.create %s: DatabaseName="%s"', [config.ThisPairName, DBConnection.DatabaseName]);
     	DBConnection.UserName:=Utf8ToAnsi(config.DBUsername);
        log('PQWriterClass.create %s: UserName="%s"', [config.ThisPairName, DBConnection.UserName]);
     	DBConnection.Password:=Utf8ToAnsi(config.DBPassword);
        log('PQWriterClass.create %s: Password="%s"', [config.ThisPairName, DBConnection.Password]);
        DBConnection.Params.Add('port='+IntToStr(config.DBHostPort));
        // Does not work!
        // [4752] PQWriterClass.create: Error "Connection to database failed (PostgreSQL: invalid connection option "timezone"
        // log('PQWriterClass.create: Setting DBConnection time zone to "' + ThisBrokerTimezone + '"');
	// DBConnection.Params.Add('timezone=''' + ThisBrokerTimezone + '''');
        log('PQWriterClass.create %s: Parameters set ... connecting ...', [config.ThisPairName]);
        try
	     	DBConnection.Open;
                DBTransaction := TSQLTransaction.Create(NIL);
  		DBTransaction.Database := DBConnection;
                isConnected:=true;
        except on E:Exception do begin
                	Log('PQWriterClass.create %s: Error "%s"', [config.ThisPairName, E.Message]);
                        isConnected:=false;
		end;
	end;
        if (isConnected) then begin
                log('PQWriterClass.create %s: Connection successful - exiting', [config.ThisPairName]);
                // A Query to get the broker id into ThisBrokerID;
                getBrokerIDQuery:=TSQLQuery.create(NIL);
                getBrokerIDQuery.DataBase:=DBConnection;
                getBrokerIDQuery.SQL.Text:='select * from t_mt4_brokers where ' +
                		'brokername=:BROKERNAME and broker_timezone=:BROKERTIMEZONE and is_demo=:ACCOUNTISDEMO';

                // A Query to insert a new broker into SQL
                insertBrokerIDQuery:=TSQLQuery.create(NIL);
                insertBrokerIDQuery.DataBase:=DBConnection;
                insertBrokerIDQuery.SQL.Text:='insert into t_mt4_brokers (brokername, broker_timezone, is_demo) values (:BROKERNAME, :BROKERTIMEZONE, :ACCOUNTISDEMO)';

                // A Query to get the Symbolid into ThisPairID;
                getPairQuery:=TSQLQuery.create(NIL);
                getPairQuery.DataBase:=DBConnection;
                getPairQuery.SQL.Text:='select * from t_mt4_pairdata where pairname=:THISPAIRNAME and broker_id=:BROKERID';

                // A Query to insert a new pair into SQL
                insertPairQuery:=TSQLQuery.create(NIL);
                insertPairQuery.DataBase:=DBConnection;
                insertPairQuery.SQL.Text:='insert into t_mt4_pairdata (broker_id, pairname, point, digits) values ' +
                				'(:BROKERID, :THISPAIRNAME, :THISPOINT, :THISDIGITS)';

                // A Query to get the alias name ID into ThisPairAliasID using a name and a broker id
                getAliasPairQuery:=TSQLQuery.create(NIL);
                getAliasPairQuery.DataBase:=DBConnection;
                getAliasPairQuery.SQL.Text:='select *, a.pairname as aliasname from t_mt4_pairdata p ' +
                	' join t_mt4_pairaliases pa using (pair_id) ' +
                        ' join t_mt4_aliasnames a using (alias_id) ' +
                        ' join t_mt4_brokers b using (broker_id) ' +
                        ' where p.pairname=:THISPAIRNAME and b.broker_id=:BROKERID';

                // A Query to get the alias name ID into ThisPairAliasID
                getAliasQuery:=TSQLQuery.create(NIL);
                getAliasQuery.DataBase:=DBConnection;
                getAliasQuery.SQL.Text:='select * from t_mt4_aliasnames a where a.pairname=:THISPAIRNAME';

                // A Query to insert a new alias name into SQL
                insertAliasQuery:=TSQLQuery.create(NIL);
                insertAliasQuery.DataBase:=DBConnection;
                insertAliasQuery.SQL.Text:='insert into t_mt4_aliasnames (pairname) values (:THISPAIRNAME)';

                // A Query to insert a new alias-pair relation into SQL
                insertAliasPairQuery:=TSQLQuery.create(NIL);
                insertAliasPairQuery.DataBase:=DBConnection;
                insertAliasPairQuery.SQL.Text:='insert into t_mt4_pairaliases (pair_id, alias_id) values (:THISPAIRID, :THISALIASID)';

                // A Query to insert a tick into SQL
                log('PQWriterClass.create %s: Creating tick insert-query', [config.ThisPairName]);
                insertTickQuery:=TSQLQuery.create(NIL);
                insertTickQuery.DataBase:=DBConnection;
                insertTickQuery.SQL.Text:='insert into t_mt4_ticks (pair_id, loctimestamp, tick_cnt, ttimestamp, isBadTick, dbid, dask, dlast, dvolume) values ' +
                			'(:PAIRID, cast(:LOCTIMESTAMP as timestamptz), :TICKCOUNTER, cast(:TIMESTAMP as timestamptz), :ISROQUETICK, :BID, :ASK, :LAST, :VOLUME)';
                			// Using this the time zone information gets lost.
                                        // '(:PAIRID, :TIMESTAMP, :BID, :ASK, :LAST, :VOLUME)';
        	log('PQWriterClass.create %s: Connected!', [config.ThisPairName]);
                lastTickSecond:=0;
                // Prepare base table contents and populate
                // the internal variables of this class
                getBrokerData();
                getPairData();
                getAliasData();
                if (not isInitalized) then begin
	        	if (ThisBrokerID<0) then begin
			        log('PQWriterClass.create %s: Could not fetch the broker ID for "%s"', [config.ThisPairName, config.ThisBrokerName]);
			        isConnected:=false;
	        	end;
		        if (ThisPairID<0) then begin
	        		log('PQWriterClass.create %s: Could not fetch the pair ID for "%s, %s"', [config.ThisPairName, ThisPairID, ThisBrokerID]);
		        	isConnected:=false;
	        	end;
                        if (ThisAliasID<0) then begin
                        	log('PQWriterClass.create %s: Could not fetch the alias ID for "%s, %s"', [config.ThisPairName, ThisPairID, ThisBrokerID]);
		        	isConnected:=false;
			end;

		end;
	end else begin
                log('PQWriterClass.create %s: Creation failed during connection establishing - exiting', [config.ThisPairName]);
	end;
end;

destructor PQWriterClass.destroy();
begin
        log('PQWriterClass.destroy %s: Destroying ...', [config.ThisPairName]);
        SessionSettingsQuery.free;
        insertTickQuery.free;
        getBrokerIDQuery.free;
        insertBrokerIDQuery.free;
        getPairQuery.free;
        insertPairQuery.free;
     	//
        log('PQWriterClass.destroy %s: Disconnecting ...', [config.ThisPairName]);
        try
                // Was es bis hier nicht zum Commit geschafft hat
                // braucht ihn wohl auch nicht... :)
                if (DBTransaction<>NIL) then begin
                	DBTransaction.Rollback;
	                DBTransaction.Free;
		end;
                if (DBConnection<>NIL) then begin
			DBConnection.Close;
                	DBConnection.Free;
		end;
	except on E:Exception do begin
        		Log('PQWriterClass.destroy %s: Error "%s"', [config.ThisPairName, E.Message]);
		end;
       	end;
        isConnected:=false;
        log('PQWriterClass.DBDisconnect %s: Disconnected...', [config.ThisPairName]);
        // inherited destroy;
end;


function PQWriterClass.writeTick(
          pSQLTick		: pSQLTickRow;
          pRetryCounter		: DWORD
) : Boolean;
var
          SecondsDelta			: Int64;
          isRoqueTick			: boolean;
          LocTimeDelta			: Double;
begin
     	if (not isConnected) then begin
        	log('PQWriterClass.writeTick %s: Not connected ...', [config.ThisPairName]);

        	exit(false);
	end;
        if (pRetryCounter>=MaxRetries) then begin
        	log('PQWriterClass.writeTick %s:  Max. retries reached "%d"', [config.ThisPairName, pRetryCounter]);
                exit(false);
        end;
        isRoqueTick:=false;
        // Calculate the difference in seconds to the last received tick.
        SecondsDelta:=pSQLTick^.MQLTick.time-LastTickSecond;
        if (SecondsDelta<>0) then begin
                if (pSQLTick^.MQLTick.time<lastTickSecond) then begin
                        // check whether we received a current tick with an older timestamp than before.
                        // This should not happen normally - but we should detect this because it
                        // gives the EA an unexecutable price as a signal.
                        log('PQWriterClass.writeTick %s: ROQUE-TICK DETECTED! old=%d, new=%d', [config.ThisPairName, lastTickSecond, pSQLTick^.MQLTick.time]);
                        isRoqueTick:=true;
                end;
	end;
        CurrTickTime:=UnixToDateTime(pSQLTick^.MQLTick.time);
        psqlTick^.TickTime:=CurrTickTime;
        CurrLocTime:=TimeStampToDateTime(pSQLTick^.localTime);
        if (PredLocTime<>0) then begin
                LocTimeDelta:=MilliSecondsBetween(PredLocTime, CurrLocTime);
	end else begin
        	TickCounter:=0;
	end;
	if (LocTimeDelta=0) then begin
                TickCounter:=TickCounter+1;
	end else begin
                TickCounter:=0;
	end;
        TickCounter:=TickCounter+pRetryCounter;
	try
                // Log Bursts only ...
                {
                if (SecondsDelta=0) then

                	Log('PQWriterClass.writeTick %s: About to write Tick predT=%.12f, currT=%.12f, predDT=%.1f, pRetry=%d',
                        	[ThisPairName, PredLocTime, CurrLocTime, LocTimeDelta, pRetryCounter]
                        );
                }
                // Primary key
                insertTickQuery.Params.ParamByName('PAIRID').AsInteger:=ThisPairID;
                insertTickQuery.Params.ParamByName('LOCTIMESTAMP').AsString:=FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', CurrLocTime) + ' ' + config.ThisMachineTimezone;
                insertTickQuery.Params.ParamByName('TICKCOUNTER').AsInteger:=TickCounter;
                // Payload
                insertTickQuery.Params.ParamByName('TIMESTAMP').AsString:=FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', CurrTickTime) + ' ' + pSQLTick^.BrokerTimeZone;
                insertTickQuery.Params.ParamByName('ISROQUETICK').AsBoolean:=isRoqueTick;
                insertTickQuery.Params.ParamByName('BID').AsFloat:=pSQLTick^.MQLTick.bid;
                insertTickQuery.Params.ParamByName('ASK').AsFloat:=pSQLTick^.MQLTick.ask;
                insertTickQuery.Params.ParamByName('LAST').AsFloat:=pSQLTick^.MQLTick.last;
                insertTickQuery.Params.ParamByName('VOLUME').AsFloat:=pSQLTick^.MQLTick.volume;
                // log('PQWriterClass.writeTick %s: Commencing ExecSQL ', [config.ThisPairName]);
                insertTickQuery.ExecSQL;
                // log('PQWriterClass.writeTick %s: Commencing Commit ', [config.ThisPairName]);
                DBTransaction.Commit;
                //
                LastTickSecond:=pSQLTick^.MQLTick.time;
                PredLocTime:=CurrLocTime;
        except on E:Exception do begin
                	log('PQWriterClass.writeTick %s: DBError "%s"', [config.ThisPairName, E.Message]);
                        log('PQWriterClass.writeTick %s: DBError pRetry=%d', [config.ThisPairName, pRetryCounter]);
                        if (DBConnection.Connected) then begin
                        	DBTransaction.Rollback;
                                log('PQWriterClass.writeTick %s: DBError but still connected - retry %d', [config.ThisPairName, pRetryCounter]);
        	                exit( writeTick(pSQLTick, pRetryCounter+1) );
                        end else begin
                                exit(false);
			end;
		end;
	end;
        {
	Log('PQWriterClass.writeTick %s: Tick written pRetry=%d',
                        	[ThisPairName, pRetryCounter]
	);
        }
        Dispose(pSQLTick);
        exit(true);
end;

procedure PQWriterClass.getBrokerData();
begin
	Log('PQWriterClass.getBrokerData %s: Invoking for Brokername="%s", Demo=%d', [config.ThisPairName, config.ThisBrokerName, config.ThisAccountIsDemo]);
	getBrokerIDQuery.Params.ParamByName('BROKERNAME').AsString:=config.ThisBrokerName;
        getBrokerIDQuery.Params.ParamByName('BROKERTIMEZONE').AsString:=config.ThisBrokerTimezone;
        getBrokerIDQuery.Params.ParamByName('ACCOUNTISDEMO').AsBoolean:=(config.ThisAccountIsDemo<>0);
        Log('PQWriterClass.getBrokerData: Opening query');
        try
        	getBrokerIDQuery.Open;
	except on E:Exception do begin
                	log('PQClass.getBrokerData %s: DBError "%s"', [config.ThisPairName, E.Message]);
                        isInitalized:=false;
                end;
	end;
        Log('PQWriterClass.getBrokerData: Query opened');
	if (getBrokerIDQuery.EOF) then begin
                // Neuen Broker anlegen und die ID erneut abholen
                Log('PQWriterClass.getBrokerData %s: Broker "%s" does not exist - creating ...', [config.ThisPairName, config.ThisBrokerName]);
                getBrokerIDQuery.close;
                try
                        insertBrokerIDQuery.Params.ParamByName('BROKERNAME').AsString:=config.ThisBrokerName;
                        insertBrokerIDQuery.Params.ParamByName('BROKERTIMEZONE').AsString:=config.ThisBrokerTimezone;
                        insertBrokerIDQuery.Params.ParamByName('ACCOUNTISDEMO').AsBoolean:=(config.ThisAccountIsDemo<>0);
                        insertBrokerIDQuery.ExecSQL;
                        DBTransaction.Commit;
                        getBrokerData();
                        exit;
		except on E:Exception do begin
                		log('PQClass.getBrokerData %s: DBError "%s"', [config.ThisPairName, E.Message]);
                	        insertBrokerIDQuery.close;
        	                isInitalized:=false;
	                        exit;
                	end;
		end;

	end;
        ThisBrokerID:=getBrokerIDQuery.FieldByName('broker_id').AsInteger;
        Log('PQWriterClass.getBrokerData %s: Fetched broker_id=%d for Broker="%s"', [config.ThisPairName, ThisBrokerID, config.ThisBrokerName]);
        getBrokerIDQuery.close;

end;


procedure PQWriterClass.getPairData();
begin
        if (not isInitalized) then
        	exit;
	Log('PQWriterClass.getPairData %s: Invoking for Pairname="%s" - broker_id=%d', [config.ThisPairName, config.ThisPairName, ThisBrokerID]);
	getPairQuery.Params.ParamByName('THISPAIRNAME').AsString:=config.ThisPairName;
        getPairQuery.Params.ParamByName('BROKERID').AsInteger:=ThisBrokerID;
        Log('PQWriterClass.getPairData %s: Opening query', [config.ThisPairName]);
        try
        	getPairQuery.Open;
	except on E:Exception do begin
                	log('PQWriterClass.getPairData %s: Open DBError "%s"', [config.ThisPairName, E.Message]);
                        isInitalized:=false;
                end;
	end;
        Log('PQWriterClass.getPairData: Query opened - fetching results ... ');
	// Die Query produziert entweder 1 oder 0 Results
	if (getPairQuery.EOF) then begin
                // Neues Pair/Timeframe anlegen und die ID erneut abholen
                Log('PQWriterClass.getPairData %s: Pair/broker_id("%s", %d) does not exist - creating ...', [config.ThisPairName, config.ThisPairName, ThisBrokerID]);
                getPairQuery.close;
                try
                        insertPairQuery.Params.ParamByName('THISPAIRNAME').AsString:=config.ThisPairName;
                        insertPairQuery.Params.ParamByName('BROKERID').AsInteger:=ThisBrokerID;
                        insertPairQuery.Params.ParamByName('THISPOINT').AsFloat:=config.ThisPairPoint;
                        insertPairQuery.Params.ParamByName('THISDIGITS').AsFloat:=config.ThisPairDigits;
                        insertPairQuery.ExecSQL;
                        DBTransaction.Commit;
                        getPairData();
                        exit;
		except on E:Exception do begin
                		log('PQWriterClass.getPairData %s: Insert DBError "%s"', [config.ThisPairName, E.Message]);
        	                isInitalized:=false;
	                        insertPairQuery.close;
                        	exit;
                	end;
		end;

	end;
        ThisPairID:=getPairQuery.FieldByName('pair_id').AsInteger;
        Log('PQWriterClass.getPairData %s: Fetched pair_id=%d for pair/broker_id("%s", %d)', [config.ThisPairName, ThisPairID, config.ThisPairName, ThisBrokerID]);
        getPairQuery.close;

end;

procedure PQWriterClass.getAliasData();
begin
        if (not isInitalized) then
        	exit;
	Log('PQWriterClass.getAliasData %s: Invoking for Pairname="%s" - broker_id=%d', [config.ThisPairName, config.ThisPairName, ThisBrokerID]);
        // This checks for a complete Alias-Pair relation
	getAliasPairQuery.Params.ParamByName('THISPAIRNAME').AsString:=config.ThisPairName;
        getAliasPairQuery.Params.ParamByName('BROKERID').AsInteger:=ThisBrokerID;
        Log('PQWriterClass.getAliasData %s: Opening Alias-Pair query', [config.ThisPairName]);
        try
        	getAliasPairQuery.Open;
	except on E:Exception do begin
                	log('PQWriterClass.getAliasData %s: Open DBError "%s"', [config.ThisPairName, E.Message]);
                end;
	end;
        Log('PQWriterClass.getAliasData %s: Query opened - fetching results ... ', [config.ThisPairName]);
	// The AliaspairQuery produces exactly 0 or 1 result
	if (getAliasPairQuery.EOF) then begin
        	getAliasPairQuery.Close;
                // Check whether we have to insert a new Alias
                // or simply a new alias-pair relation
                getAliasQuery.Params.ParamByName('THISPAIRNAME').AsString:=config.ThisPairName;
                Log('PQWriterClass.getAliasData %s: Opening Alias query', [config.ThisPairName]);
	        try
	        	getAliasQuery.Open;
		except on E:Exception do begin
        	        	log('PQWriterClass.getAliasData %s: Open DBError "%s"', [config.ThisPairName, E.Message]);
                                isInitalized:=false;
	                end;
		end;
        	Log('PQWriterClass.getAliasData %s: Query opened - fetching results ... ', [config.ThisPairName]);
                if (getAliasQuery.EOF) then begin
                	// Alias name does not exist - create!
                        Log('PQWriterClass.getAliasData %s: Aliasname does not exist - creating new ... ', [config.ThisPairName]);
                        try
                        	insertAliasQuery.Params.ParamByName('THISPAIRNAME').AsString:=config.ThisPairName;
	                        insertAliasQuery.ExecSQL;
        	                DBTransaction.Commit();
                	        InsertAliasQuery.Close();
                        	getAliasQuery.Close();
	                        getAliasData();
        	                // No recursion here!
                	        exit;
                        except on E:Exception do begin
                        		log('PQWriterClass.getAliasData %s: Insert DBError "%s"', [config.ThisPairName, E.Message]);
                                        isInitalized:=false;
				end;
			end;
		end else begin
                	ThisAliasID:=getAliasQuery.FieldByName('alias_id').AsInteger;
                        Log('PQWriterClass.getAliasData %s: Fetched alias_id=%d for newly created alias name ... ', [config.ThisPairName, ThisAliasID]);
                        getAliasQuery.close;
		end;

                Log('PQWriterClass.getAliasData %s: Alias relation for Pair/broker_id("%s", %d) does not exist - creating ...', [config.ThisPairName, config.ThisPairName, ThisBrokerID]);
                try
                        insertAliasPairQuery.Params.ParamByName('THISPAIRID').AsInteger:=ThisPairID;
                        insertAliasPairQuery.Params.ParamByName('THISALIASID').AsInteger:=ThisAliasID;
                        insertAliasPairQuery.ExecSQL;
                        DBTransaction.Commit;
                        insertAliasPairQuery.Close();
                        getAliasData();
                        exit;
		except on E:Exception do begin
                	log('PQWriterClass.getAliasData %s: Insert DBError "%s"', [config.ThisPairName, E.Message]);
                        insertAliasPairQuery.close;
                        isInitalized:=false;
                        exit;
                	end;
		end;
	end;
        try
	        ThisAliasID:=getAliasPairQuery.FieldByName('alias_id').AsInteger;
        	ThisAliasName:=getAliasPairQuery.FieldByName('aliasname').AsString;
	except on E:Exception do begin
                	log('PQWriterClass.getAliasData %s: Insert DBError "%s"', [config.ThisPairName, E.Message]);
                        getAliasPairQuery.close;
                        isInitalized:=false;
                        exit;
                end;
	end;
        Log('PQWriterClass.getAliasData %s: Fetched alias_id=%d (%s) for pair/pair_id/broker_id("%s", %d, %d)', [config.ThisPairName, ThisAliasID, ThisAliasName, config.ThisPairName, ThisPairID, ThisBrokerID]);
end;

end.

