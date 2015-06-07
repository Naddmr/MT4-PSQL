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
unit upq_process_dispatcher;

{$mode objfpc}{$H+}

interface

uses
        cMem,
        Classes,
        Windows,
        SysUtils,
        DateUtils,
        uPQWriterDefinitions;
type
// ############################################################################
PQProcDispatcherClass = Class
protected
        ConfigFileName			: AnsiString;
        config				: PQConfigClass;
        isValid				: Boolean;
        BrokerSHMObject			: PQShareMemClass;
        PairSHMObject			: PQShareMemClass;
        TickSHMObject			: PQShareMemClass;
public
	constructor create(
                pConfigFileName		: pWideChar;
		pEAName 		: pWideChar;
		pPairName 		: pWideChar;
                pBrokerName		: pWideChar;
                pIsDemo			: DWORD;
                pPoint			: Double;
        	pDigits			: Double
	);
        //
	destructor Destroy(); override;
        //
        procedure DispatchTick(
                pMQLTick	: pMQLTickRow
        );
        //
        function getIsvalid() : Integer;
        procedure RegisterBroker();
        procedure RegisterPair();
private
        procedure Log(AMessage: WideString);
	procedure Log(AMessage: WideString; AArgs: array of const);
End;
implementation
//
// ######################### PQProcDispatcherClass
constructor PQProcDispatcherClass.create(
        pConfigFileName		: pWideChar;
	pEAName 		: pWideChar;
        pPairName 		: pWideChar;
        pBrokerName		: pWideChar;
        pIsDemo			: DWORD;
        pPoint			: Double;
        pDigits			: Double
);
var
        i	: DWORD;
begin
        log('PQProcDispatcherClass.create %s: Invoking ...', [pPairName]);
        self.ConfigFileName:=Utf8ToAnsi(pConfigFileName);
	self.config:=PQConfigClass.Create(
        	'',		// pBrokerTimeZone,
                '',		// pMachineTimeZone,
		pEAName,
		pPairName,
                pBrokerName,
                pIsDemo,
                0,		// pTimeframe,
                pPoint,
        	pDigits,
                500,		// pPollingInterval,
		'',		// pDBHostname,
		5432,		// pDBHostPort,
		'',		// pDBName,
		'',		// pDBUsername,
		'',		// pDBPassword,
                100		// pMaxRetries
        );
        log('PQProcDispatcherClass.create %s: Settings file is "%s"', [pPairName, self.ConfigFileName]);
        self.config.ReadSettings(self.ConfigFileName);
        BrokerSHMObject:=PQShareMemClass.create(self.config.BrokerShareMemName, sizeof(TSQLBrokerRow), config.MaxBrokers);
        PairSHMObject:=PQShareMemClass.create(self.config.PairShareMemName, sizeof(TSQLPairRow), config.MaxBrokers*config.MaxCharts);
        TickSHMObject:=PQShareMemClass.create(self.config.TickShareMemName, sizeof(TSQLTickRow), config.MaxBrokers*config.MaxCharts*config.MaxTicks);
        isValid:=(BrokerSHMObject<>NIL) and (PairSHMObject<>NIL) and (TickSHMObject<>NIL);
        if (isValid) then begin
        	config.ThisBrokerID:=0;
	        config.ThisPairID:=0;
        	// Register broker
	        log('PQProcDispatcherClass.create %s: Registering broker %s ...', [config.ThisPairName, config.ThisBrokerName]);
        	i:=0;
	        while (config.ThisBrokerID=0) and (i<=config.MaxRetries) do begin
			self.RegisterBroker();
	                Sleep(config.PollingInterval);
                	inc(i);
		end;
	        if (config.ThisBrokerID<>0) then begin
                	log('PQProcDispatcherClass.create %s: Registering pair on Broker %d ...', [config.ThisPairName, config.ThisBrokerID]);
        	        i:=0;
	        	while (config.ThisPairID=0) and (i<=config.MaxRetries) do begin
	        	        self.RegisterPair();
        		        Sleep(500);
	                        inc(i);
			end;
        	        self.isValid:=(config.ThisPairID<>0);
	                if not self.isValid then
                	        log('PQProcDispatcherClass.create %s: Could not register pair of broker "%s" ...', [config.ThisPairName, config.ThisBrokerName]);;
        	end else begin
			self.isValid:=false;
                	log('PQProcDispatcherClass.create %s: Could not register broker %s ...', [config.ThisPairName, config.ThisBrokerName]);
		end;
	end else begin
		log('PQProcDispatcherClass.create %s: Could not get one or more shared memory regions!', [config.ThisPairName]);
	end;
end;

destructor PQProcDispatcherClass.destroy();
begin
        log('PQProcDispatcherClass.stop %s: Destroying ...', [config.ThisPairName]);
        self.isValid:=false;
        if (BrokerSHMObject<>NIL) then
        	FreeAndNil(BrokerSHMObject);
        if (PairSHMObject<>NIL) then
        	FreeAndNil(PairSHMObject);
        if (TickSHMObject<>NIL) then
        	FreeAndNil(TickSHMObject);
        log('PQProcDispatcherClass.stop %s: Destroyed ...', [config.ThisPairName]);
        inherited destroy;
end;

procedure PQProcDispatcherClass.RegisterBroker();
var
        p	: pSQLBrokerRow;
        fp	: pFIFORecord;
        i	: dword;
        found	: boolean;
begin
	found:=false;
        i:=0;
        // rs:=BrokerSHMObject.wRowSize;
        fp:=BrokerSHMObject.FiFoPtr;
        p:=BrokerSHMObject.RowPtr;
        log('PQProcDispatcherClass.RegisterBroker %s: Invoking ...', [config.ThisPairName]);
        try
                BrokerSHMObject.Lock();
                while (i<fp^.write_idx) and not found do begin
                	found:=	(p^.broker_name=config.ThisBrokerName) and
                        	(p^.is_demo=(config.ThisAccountIsDemo<>0) ) and
                                (p^.broker_timezone=config.ThisBrokerTimeZone);
                        if not found then begin
                        	inc(p);
                        	inc(i);
			end;
		end;
                if not found then begin
                	// Register broker into SHM
                        p:=BrokerSHMObject.RowPtr;
                        inc(p, fp^.write_idx);
                        log('PQProcDispatcherClass.RegisterBroker %s: Registering into SHM at ptr=%p ...', [config.ThisPairName, p]);
                        p^.broker_id:=0;
                        p^.broker_name:=config.ThisBrokerName;
                        p^.broker_timezone:=config.ThisBrokerTimeZone;
                        p^.is_demo:=(config.ThisAccountIsDemo<>0);
                        inc(fp^.write_idx);
                end;
                if (p^.broker_id<>0) then begin
                	config.ThisBrokerID:=p^.broker_id;
                        log('PQProcDispatcherClass.RegisterBroker %s: Found Broker in SHM at id=%d ...', [config.ThisPairName, config.ThisBrokerID]);
		end;
	finally
        	BrokerSHMObject.UnLock();
	end;
end;

procedure PQProcDispatcherClass.RegisterPair();
var
        p	: pSQLPairRow;
        fp	: pFIFORecord;
        i	: dword;
        found	: boolean;
begin
	found:=false;
        i:=0;
        // rs:=BrokerSHMObject.wRowSize;
        fp:=PairSHMObject.FiFoPtr;
        p:=PairSHMObject.RowPtr;
        log('PQProcDispatcherClass.RegisterPair %s: Invoking ...', [config.ThisPairName]);
        try
                PairSHMObject.Lock();
                while (i<fp^.write_idx) and not found do begin
                	found:= (p^.broker_id=config.ThisBrokerID) and
                                (p^.pair_name=config.ThisPairName) and
                        	(p^.point=config.ThisPairPoint) and
                        	(p^.Digits=config.ThisPairDigits);
                        if not found then begin
                        	inc(p);
                        	inc(i);
			end;
		end;
                if not found then begin
                	// Register broker into SHM
                        p:=PairSHMObject.RowPtr;
                        inc(p, fp^.write_idx);
                        log('PQProcDispatcherClass.RegisterPair %s: Registering into SHM at ptr=%p ...', [config.ThisPairName, p]);
                        p^.pair_id:=0;
                        p^.broker_id:=config.ThisBrokerID;
                        p^.pair_name:=config.ThisPairName;
                        p^.point:=config.ThisPairPoint;
                        p^.Digits:=config.ThisPairDigits;
                        inc(fp^.write_idx);
                end;
                if (p^.pair_id<>0) then begin
                	config.ThisPairID:=p^.pair_id;
                        log('PQProcDispatcherClass.RegisterPair %s: Found pair in SHM at id=%d ...', [config.ThisPairName, config.ThisPairID]);
		end;
	finally
        	PairSHMObject.UnLock();
	end;

end;

procedure PQProcDispatcherClass.DispatchTick(
                pMQLTick	: pMQLTickRow
        );
var
        tp	: tSQLTickRow;
        p	: pSQLTickRow;
        fp	: pFIFORecord;
begin
        if (self.isValid) then begin
		tp.MQLTick:=pMQLTick^;
	        tp.localTime:=DateTimeToTimeStamp(Now);
        	tp.BrokerTimeZone:=config.ThisBrokerTimeZone;
                tp.TickTime:=UnixToDateTime(pMQLTick^.time);
		tp.pairID:=config.ThisPairID;
        	// AddRing takes care of lockings ...
                //p:=TickSHMObject.RowPtr;
                //fp:=TickSHMObject.FiFoPtr;
                //inc(p, fp^.write_idx);
                //log('PQProcDispatcherClass.DispatchTick %s: Dispatching into SHM at ptr=%p, pair_id=%d',
                //	[config.ThisPairName, p, tp.pairID]
                //);
	        TickSHMObject.AddRing(@tp);
                //log('PQProcDispatcherClass.DispatchTick %s: Dispatched into SHM at ptr=%p, pair_id=%d',
                //	[config.ThisPairName, p, p^.pairID]
                //);

	end;
end;

function PQProcDispatcherClass.getIsvalid() : Integer;
var
        rc		: Integer;
begin
        rc:=0;
        if (self.isValid) then
                rc:=1;
        log('PQProcDispatcherClass.getIsvalid: rc=%d', [ rc ] );
        exit(rc);
end;

// log a message to the debug monitor
procedure PQProcDispatcherClass.Log(AMessage: WideString);
begin
	OutputDebugStringW( PWideChar(AMessage) );
end;

// log a formatted message to the debug monitor
procedure PQProcDispatcherClass.Log(AMessage: WideString; AArgs: array of const);
begin
	Log(Format(AMessage, AArgs));
end;


end.

