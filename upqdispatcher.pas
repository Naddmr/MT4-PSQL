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
        // Parameters
        ThisBrokerTimezone		: AnsiString;
        ThisBrokerName			: AnsiString;
        ThisAccountIsdemo		: DWORD;
	ThisEAName			: AnsiString;
	ThisPairName			: AnsiString;
        ThisTimeframe			: Integer;
        ThisPairPoint			: Double;
        ThisPairDigits			: Double;
        DBHostname			: AnsiString;
        DBHostPort			: Integer;
        DBName				: AnsiString;
        DBUserName			: AnsiString;
        DBPassword			: AnsiString;
        MaxRetries			: DWORD;
        PollingInterval			: DWORD;
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
                pBrokerTimeZone		: WideString;
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
        ThisPairName			: AnsiString;

public
        isValid				: Boolean;
	constructor create(
                pBrokerTimeZone		: WideString;
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
private
End;

implementation
//
// ######################### PQWriterThreadClass
constructor PQWriterThreadClass.create(
        pBrokerTimeZone		: WideString;
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
var
        i			: DWORD;
begin
	log('PQWriterThreadClass.create %s: Invoking ...', [ThisPairName]);
        ThisBrokerTimezone:=pBrokerTimeZone;
        ThisBrokerName:=pBrokerName;
        ThisAccountIsDemo:=pIsDemo;
     	ThisEAName:=pEAName;
     	ThisPairName:=pPairName;
        ThisTimeframe:=pTimeFrame;
        ThisPairPoint:=pPoint;
        ThisPairDigits:=pDigits;
     	DBHostname:=Utf8ToAnsi(pDBHostname);
     	DBHostPort:=pDBHostPort;
     	DBName:=Utf8ToAnsi(pDBName);
     	DBUserName:=Utf8ToAnsi(pDBUsername);
     	DBPassword:=Utf8ToAnsi(pDBPassword);
        MaxRetries:=pMaxRetries;
        PollingInterval:=pPollingInterval;
        isStopping:=false;
        isStopped:=false;
        isValid:=false;
        isWriting:=false;
        //
        PQWriter:=NIL;
        TickQueue:=NIL;
        InitializeCriticalSection(PushPullCriticalSection);
        PQWriter:=ReConnect();
        i:=1;
        while (not PQWriter.isValid) and (i<=MaxRetries) do begin
        	Sleep(PollingInterval);
                PQWriter:=ReConnect();
	end;
	if (PQWriter.isValid) then begin
	        //
	        TickQueue:=TFPList.Create();
	        inherited Create(false);
                self.start;
	        log('PQWriterThreadClass.create %s: Started ...', [ThisPairName]);
                isValid:=true;
        end else begin
        	log('PQWriterThreadClass.create %s: Failed to initialize the database connection ...', [ThisPairName]);
	end;
end;

destructor PQWriterThreadClass.Destroy();
var
        i	: DWORD;
Begin
	log('PQWriterThreadClass.Destroy %s: Invoking ...', [ThisPairName]);
        isStopping:=true;
        i:=1;
        while (not isStopped) and (i<=MaxRetries) do begin
		// Awake the thread loop again to get it dead :)
                self.resume;
                sleep(PollingInterval);
                log('PQWriterThreadClass.Destroy %s: Waiting ...', [ThisPairName]);
                inc(i);
	end;
        if (i>=MaxRetries) then begin
        	log('PQWriterThreadClass.Destroy %s: Timeout - stopping immediately...', [ThisPairName]);
                self.Terminate;
	end;
        if (TickQueue<>NIL) then
		TickQueue.free;
        if (PQWriter<>NIL) then
        	PQWriter.free;
        DeleteCriticalSection(PushPullCriticalSection);
	inherited Destroy;
        log('PQWriterThreadClass.Destroy %s: Invoking ...', [ThisPairName]);
end;


function PQWriterThreadClass.Reconnect() : PQWriterClass;
begin
	// Destroy old PQWriter when not NIL.
        if (PQWriter<>NIL) then begin
                PQWriter.Free;
	end;
        // Create a new PQWriter instance and try a new
        exit(PQWriterClass.Create(
        			ThisBrokerTimezone,
     				ThisEAName,
                                ThisPairName,
                                ThisBrokerName,
                                ThisAccountIsdemo,
                                ThisTimeframe,
                                ThisPairPoint,
                                ThisPairDigits,
                                DBHostname,
                                DBHostPort,
                                DBName,
                                DBUsername,
                                DBPassword,
                                MaxRetries
		)
     	);
end;

procedure PQWriterThreadClass.Execute();
var
        SQLTick		: pSQLTickRow;
        i		: DWORD;
begin
        log('PQWriterThreadClass.Execute %s: Starting worker loop ...', [ThisPairName]);
        while (not isStopping) do begin
                if (TickQueue.Count>0) then begin
                        i:=0;
	        	// log('PQWriterThreadClass.Execute %s: Queue-Len = %d', [ThisPairName, TickQueue.Count]);
			SQLTick:=PopTick();
			while (SQLTick<>NIL) and (not isStopping) do begin
	                        isWriting:=true;
		        	// log('PQWriterThreadClass.Execute %s: Writing ...', [ThisPairName]);
		                if (not PQWriter.writeTick(SQLTick, 0)) then begin
		                        // Reconnect-Loop
			                log('PQWriterThreadClass.Execute %s: Retrying ...', [ThisPairName]);
		        	        PQWriter:=Reconnect();
		                	sleep(PollingInterval);
		                        // TODO: Logging, Alerting ...
			        end else begin
		        	        SQLTick:=PopTick();
				end;
                                i:=i+1;
			end;
	                isWriting:=false;
                        // log('PQWriterThreadClass.Execute %s: Wrote %d ticks', [ThisPairName, i]);
                        // self.suspend;
		end;
		Sleep(PollingInterval);
	end;
        log('PQWriterThreadClass.Execute %s: Terminating ...', [ThisPairName]);
        isStopped:=true;
end;

procedure PQWriterThreadClass.pushTick(pSQLTick	: pSQLTickRow);
begin
        // log('PQWriterThreadClass.pushTick %s: Invoking ...', [ThisPairName]);
        EnterCriticalSection(PushPullCriticalSection);
        // Push the tick row
        TickQueue.Add(pSQLTick);
        // if (not isWriting) then self.resume();
        LeaveCriticalSection(PushPullCriticalSection);
        // log('PQWriterThreadClass.pushTick %s: Exiting ql=%d ...', [ThisPairName, TickQueue.Count]);

end;

function PQWriterThreadClass.PopTick() : pSQLTickRow;
var
  	rc	: pSQLTickRow;
begin
        // log('PQWriterThreadClass.PopTick %s: Invoking ...', [ThisPairName]);
        EnterCriticalSection(PushPullCriticalSection);
        // Pull a tick row - return NIL when no tick available
        rc:=NIL;
        if (TickQueue.Count>0) then begin
		rc:=TickQueue.Items[0];
                TickQueue.Delete(0);
	end;
        LeaveCriticalSection(PushPullCriticalSection);
        // log('PQWriterThreadClass.PopTick %s: Exiting ...', [ThisPairName]);
        exit(rc);
end;

//
// ######################### PQDispatcher
constructor PQDispatcher.create(
        pBrokerTimeZone		: WideString;
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
        ThisPairName:=Utf8ToAnsi(pPairName);
     	log('PQDispatcher.create %s: Invoking ...', [ThisPairName]);
        isValid:=false;
        PQWriterThread:=PQWriterThreadClass.Create(
        	pBrokerTimeZone,
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
        if (PQWriterThread.isValid) then begin
	        PQWriterThread.Start;
		log('PQDispatcher.create %s: Created ...', [ThisPairName]);
                isValid:=true;
	end else begin
        	log('PQDispatcher.create %s: Error during Thread initialisation ...', [ThisPairName]);
                isValid:=false;
	end;
end;

destructor PQDispatcher.destroy();
begin
        log('PQDispatcher.stop %s: Destroying ...', [ThisPairName]);
        PQWriterThread.Free;
        inherited destroy;
        log('PQDispatcher.stop %s: Destroyed ...', [ThisPairName]);
end;

procedure PQDispatcher.DispatchTick(
                pSQLTick		: pSQLTickRow
        );
begin
        if (isValid) then
        	PQWriterThread.PushTick(pSQLTick);
end;



end.

