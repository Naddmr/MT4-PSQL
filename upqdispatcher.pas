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
unit uPQDispatcher;

{$mode objfpc}{$H+}

interface

uses
        cMem,
        Classes,
        Windows,
        SysUtils,
        DateUtils,
        uPQWriterDefinitions,
        uPQClass;
type


// ############################################################################
PQWriterThreadClass = Class (TThread)
protected
        // Parameters are taken from the parent now...
        config				: PQConfigClass;
        // Own variables
        PQWriter			: PQWriterClass;
        TickQueue			: TFPList;
        isStopping			: Boolean;
        isStopped			: Boolean;
        isWriting			: Boolean;
        PushPullCriticalSection		: TRTLCriticalSection;
public
        isValid				: Boolean;
        constructor create(
                pConfig		: PQConfigClass
	); reintroduce;
        destructor Destroy(); Override;
        //
        procedure Execute(); Override;
        //
        procedure pushTick(pSQLTick	: pSQLTickRow);
        //
        function PopTick() : pSQLTickRow;
private
        Function ReConnect() : PQWriterClass;
end;
// ############################################################################
PQDispatcher = Class
protected
        PQWriterThread			: PQWriterThreadClass;
        config				: PQConfigClass;
        isValid				: Boolean;
public

	constructor create(
                pBrokerTimeZone		: WideString;
                pMachineTimeZone	: WideString;
		pEAName 		: WideString;
		pPairName 		: WideString;
                pBrokerName		: WideString;
                pIsDemo			: DWORD;
                pTimeframe		: Integer;
                pPoint			: Double;
        	pDigits			: Double;
                pPollingInterval	: DWORD;
		pDBHostname		: WideString;
		pDBHostPort		: Integer;
		pDBName			: WideString;
		pDBUsername		: WideString;
		pDBPassword		: WideString;
                pMaxRetries		: DWORD
	);
        //
	destructor Destroy(); override;
        //
        procedure DispatchTick(
                pSQLTick		: pSQLTickRow
        );
        //
        function getIsvalid() : Integer;
private
End;
implementation
//
// ######################### PQDispatcher
constructor PQDispatcher.create(
        pBrokerTimeZone		: WideString;
        pMachineTimeZone	: WideString;
	pEAName 		: WideString;
        pPairName 		: WideString;
        pBrokerName		: WideString;
        pIsDemo			: DWORD;
        pTimeFrame		: Integer;
        pPoint			: Double;
        pDigits			: Double;
        pPollingInterval	: DWORD;
        pDBHostname		: WideString;
        pDBHostPort		: Integer;
        pDBName			: WideString;
        pDBUsername		: WideString;
        pDBPassword		: WideString;
        pMaxRetries		: DWORD
);
begin
	self.config:=PQConfigClass.Create(
        	pBrokerTimeZone,
                pMachineTimeZone,
		pEAName,
		pPairName,
                pBrokerName,
                pIsDemo,
                pTimeframe,
                pPoint,
        	pDigits,
                pPollingInterval,
		pDBHostname,
		pDBHostPort,
		pDBName,
		pDBUsername,
		pDBPassword,
                pMaxRetries
        );
	log('PQWriterThreadClass.create %s: Invoking ...', [config.ThisPairName]);
        //
     	log('PQDispatcher.create %s: Invoking ...', [config.ThisPairName]);
        self.isValid:=false;
        PQWriterThread:=PQWriterThreadClass.Create(self.config);
        if (PQWriterThread.isValid) then begin
	        PQWriterThread.Start;
                self.isValid:=true;
		log('PQDispatcher.create %s: Successfully created new writer thread, isValid=%d ...', [config.ThisPairName, Integer(self.isValid)]);
	end else begin
                self.isValid:=false;
                log('PQDispatcher.create %s: Error during Thread initialisation isValid=%d ...', [config.ThisPairName, Integer(self.isValid)]);
	end;
end;

destructor PQDispatcher.destroy();
begin
        log('PQDispatcher.stop %s: Destroying ...', [config.ThisPairName]);
        self.isValid:=false;
        PQWriterThread.Free;
        log('PQDispatcher.stop %s: Destroyed ...', [config.ThisPairName]);
        inherited destroy;
end;

procedure PQDispatcher.DispatchTick(
                pSQLTick		: pSQLTickRow
        );
begin
        if (isValid) then begin
                // store an additional timestamp of the local time
     		// in the tick row to derive the milliseconds from there.
     		pSQLTick^.localTime:=DateTimeToTimeStamp(Now);
                pSQLTick^.BrokerTimeZone:=config.ThisBrokerTimeZone;
        	PQWriterThread.PushTick(pSQLTick);
	end;
end;

function PQDispatcher.getIsvalid() : Integer;
var
        rc		: Integer;
begin
        rc:=0;
        if (self.isValid) then
                rc:=1;
        log('PQDispatcher.getIsvalid: rc=%d', [ rc ] );
        exit(rc);
end;

//
// ######################### PQWriterThreadClass
constructor PQWriterThreadClass.create(
        pConfig		: PQConfigClass
);
begin
        isStopping:=false;
        isStopped:=false;
        isValid:=false;
        isWriting:=false;
        self.config:=pConfig;
        //
        PQWriter:=NIL;
        TickQueue:=NIL;
        InitializeCriticalSection(PushPullCriticalSection);
        PQWriter:=self.ReConnect();
 //       i:=1;
 //       while (not PQWriter.isValid) and (i<=(MaxRetries div 10) ) do begin
 //       	Sleep(PollingInterval);
 //               PQWriter:=self.ReConnect();
	//end;
	if (PQWriter.isValid) then begin
	        //
	        TickQueue:=TFPList.Create();
	        inherited Create(false);
                self.start;
	        log('PQWriterThreadClass.create %s: Started ...', [config.ThisPairName]);
                isValid:=true;
        end else begin
        	log('PQWriterThreadClass.create %s: Failed to initialize the database connection ...', [config.ThisPairName]);
	end;
end;

destructor PQWriterThreadClass.Destroy();
var
        i	: DWORD;
Begin
	log('PQWriterThreadClass.Destroy %s: Invoking to destroy thread...', [config.ThisPairName]);
        isStopping:=true;
        if (self.isValid) then begin
	        i:=1;
	        while (not isStopped) and (i<=config.MaxRetries) do begin
			// Awake the thread loop again to get it dead :)
	                self.resume;
	                sleep(config.PollingInterval);
	                log('PQWriterThreadClass.Destroy %s: Waiting for thread termination ...', [config.ThisPairName]);
	                inc(i);
		end;
	        if (i>=config.MaxRetries) then begin
        		log('PQWriterThreadClass.Destroy %s: Timeout - stopping immediately...', [config.ThisPairName]);
			self.Terminate;
		end;
        end;
        if (TickQueue<>NIL) then
		TickQueue.free;
        if (PQWriter<>NIL) then
        	PQWriter.free;
        DeleteCriticalSection(PushPullCriticalSection);
        log('PQWriterThreadClass.Destroy %s: Destroyed thread ...', [config.ThisPairName]);
	inherited Destroy;

end;


function PQWriterThreadClass.Reconnect() : PQWriterClass;
begin
	// Destroy old PQWriter when not NIL.
        if (PQWriter<>NIL) then begin
                log('PQWriterThreadClass.Reconnect %s: destroying old connection ...', [config.ThisPairName]);
                PQWriter.Free;
	end;
        // Create a new PQWriter instance and try a new
        log('PQWriterThreadClass.Reconnect %s: Creating new connection ...', [config.ThisPairName]);
        exit(PQWriterClass.Create(config));
end;

procedure PQWriterThreadClass.Execute();
var
        SQLTick		: pSQLTickRow;
        i		: DWORD;
begin
        log('PQWriterThreadClass.Execute %s: Starting worker loop ...', [config.ThisPairName]);
        while (not isStopping) do begin
                if (TickQueue.Count>0) then begin
                        i:=0;
	        	// log('PQWriterThreadClass.Execute %s: Queue-Len = %d', [parent.ThisPairName, TickQueue.Count]);
			SQLTick:=PopTick();
			while (SQLTick<>NIL) and (not isStopping) do begin
	                        isWriting:=true;
		        	// log('PQWriterThreadClass.Execute %s: Writing ...', [parent.ThisPairName]);
		                if (not PQWriter.writeTick(SQLTick, 0)) then begin
		                        // Reconnect-Loop
			                log('PQWriterThreadClass.Execute %s: Retrying ...', [config.ThisPairName]);
		        	        PQWriter:=Reconnect();
		                	sleep(config.PollingInterval);
		                        // TODO: Logging, Alerting ...
			        end else begin
		        	        SQLTick:=PopTick();
				end;
                                i:=i+1;
			end;
	                isWriting:=false;
                        // log('PQWriterThreadClass.Execute %s: Wrote %d ticks', [parent.ThisPairName, i]);
                        // self.suspend;
		end;
		Sleep(config.PollingInterval);
	end;
        log('PQWriterThreadClass.Execute %s: Terminating ...', [config.ThisPairName]);
        isStopped:=true;
end;

procedure PQWriterThreadClass.pushTick(pSQLTick	: pSQLTickRow);
begin
        // log('PQWriterThreadClass.pushTick %s: Invoking ...', [parent.ThisPairName]);
        EnterCriticalSection(PushPullCriticalSection);
        // Push the tick row
        TickQueue.Add(pSQLTick);
        // if (not isWriting) then self.resume();
        LeaveCriticalSection(PushPullCriticalSection);
        // log('PQWriterThreadClass.pushTick %s: Exiting ql=%d ...', [parent.ThisPairName, TickQueue.Count]);

end;

function PQWriterThreadClass.PopTick() : pSQLTickRow;
var
  	rc	: pSQLTickRow;
begin
        // log('PQWriterThreadClass.PopTick %s: Invoking ...', [parent.ThisPairName]);
        EnterCriticalSection(PushPullCriticalSection);
        // Pull a tick row - return NIL when no tick available
        rc:=NIL;
        if (TickQueue.Count>0) then begin
		rc:=TickQueue.Items[0];
                TickQueue.Delete(0);
	end;
        LeaveCriticalSection(PushPullCriticalSection);
        // log('PQWriterThreadClass.PopTick %s: Exiting ...', [parent.ThisPairName]);
        exit(rc);
end;



end.

