unit uMT4_PQ_ThreadClass;

{$mode objfpc}{$H+}

interface

uses
	cMem,
 	Windows,
        Classes,
        SysUtils,
	sqldb,
        pqconnection,
        uPQWriterDefinitions,
        // umt4_pq_writerwindow,
        uMT4_PQ_WriterClass,
        umt4_PQ_QueueManager;
type
MT4PQWriterThreadClass = Class (TThread)
protected
        Parent				: MT4PQueueManagerClass;
        config				: PQConfigClass;
        // Own variables
        isStopping			: Boolean;
        isStopped			: Boolean;
        isWriting			: Boolean;
        MT4PQWriter			: MT4PQWriterClass;
public
        isValid				: Boolean;
        constructor create(pParent : MT4PQueueManagerClass); reintroduce;
        destructor Destroy(); Override;
        //
        procedure Execute(); Override;
private
        procedure Reconnect();
        // log a message to the debug monitor
	procedure Log(AMessage: WideString);
	procedure Log(AMessage: WideString; AArgs: array of const);
end;
MT4PQPairTimestampClass = Class(TFPList)
protected
        pairTimestamps			: TFPList;
public


end;

implementation

constructor MT4PQWriterThreadClass.create(pParent : MT4PQueueManagerClass);
begin
        self.log('MT4PQWriterThreadClass.Create: Invoking ...');
        Parent:=pParent;
	config:=Parent.config;
        isValid:=false;
        isWriting:=false;
        isStopping:=false;
        isStopped:=false;
        self.log('MT4PQWriterThreadClass.Create: Connecting to DB ...');
	self.Reconnect();
        inherited create(false);
        self.log('MT4PQWriterThreadClass.Create: Starting ...');
        self.start;
        self.log('MT4PQWriterThreadClass.Create: Done ...');
end;

destructor MT4PQWriterThreadClass.Destroy;
var
	i		: DWORD;
begin
        isStopping:=true;
        i:=1;
        while (not isStopped) and (i<=config.MaxRetries) do begin
		// Awake the thread loop again to get it dead :)
                self.resume;
                sleep(config.PollingInterval);
                self.log('MT4PQWriterThreadClass.Destroy: Waiting ...');
                inc(i);
	end;
        if (i>=config.MaxRetries) then begin
        	self.log('MT4PQWriterThreadClass.Destroy: Timeout - stopping immediately...');
                self.Terminate;
	end;
        if (MT4PQWriter<>NIL) then
        	FreeAndNil(MT4PQWriter);
        self.log('MT4PQWriterThreadClass.Destroy: Done ...');
        inherited Destroy;
end;

procedure MT4PQWriterThreadClass.Execute();
var
 	SQLTick		: pSQLTickRow;
        i		: Integer;
begin
        self.log('PQWriterThreadClass.Execute: Starting worker loop ...');
        while (not isStopping) do begin
                // self.log('MT4PQWriterThreadClass.Execute: Queue-Len = %d', [parent.OutQueueLength()]);
                if (Parent.OutQueueLength()>0) then begin
                        i:=0;
	        	// self.log('MT4PQWriterThreadClass.Execute: Queue-Len = %d', [parent.OutQueueLength()]);
			SQLTick:=Parent.PopTick();
			while (SQLTick<>NIL) and (not isStopping) do begin
	                        isWriting:=true;
		        	// self.log('PQWriterThreadClass.Execute: Writing ...');
		                if (not MT4PQWriter.writeTick(SQLTick, 0) ) then begin
		                        // Reconnect-Loop
			                self.log('PQWriterThreadClass.Execute: Retrying ...');
		        	        self.Reconnect();
		                	sleep(config.PollingInterval);
		                        // TODO: Logging, Alerting ...
			        end else begin
                                        EnterCriticalSection(parent.OutQueueCriticalSection);
                                        inc(parent.TicksWritten);
                                        LeaveCriticalSection(parent.OutQueueCriticalSection);
		        	        SQLTick:=parent.PopTick();
				end;
                                i:=i+1;
			end;
	                isWriting:=false;
                        // self.log('PQWriterThreadClass.Execute: Wrote %d ticks', [i]);
                        // self.suspend;
		end;
		Sleep(config.PollingInterval);
	end;
        self.log('PQWriterThreadClass.Execute: Terminating ...');
        isStopped:=true;
end;

procedure MT4PQWriterThreadClass.Reconnect();
begin
	// Destroy old PQWriter when not NIL.
        if (MT4PQWriter<>NIL) then begin
                FreeAndNil(MT4PQWriter);
	end;
        // Create a new PQWriter instance and try a new
        MT4PQWriter:=MT4PQWriterClass.Create(self.config);
end;

// log a message to the debug monitor
procedure MT4PQWriterThreadClass.Log(AMessage: WideString);
begin
	OutputDebugStringW( PWideChar(AMessage) );
end;

// log a formatted message to the debug monitor
procedure MT4PQWriterThreadClass.Log(AMessage: WideString; AArgs: array of const);
begin
	Log(Format(AMessage, AArgs));
end;

end.

