unit umt4_pq_writerwindow;

{$mode objfpc}{$H+}

interface

uses
        cMem,
	Windows,
        Classes,
        SysUtils,
        FileUtil,
        Forms,
        Controls,
        Graphics,
        Dialogs,
        StdCtrls,
        LCLProc,
        uPQWriterDefinitions;


type

{ TfrmWriterWindow }

TfrmWriterWindow = class(TForm)
	btnOpenSettingFile: TButton;
	labCurrChartCountDisplay: TLabel;
	labMaxCurrentQueueLengthDisplay: TLabel;
	labCurrBrokerCountDisplay: TLabel;
	labMaxTicksDisplay: TLabel;
	labMaxTicks: TLabel;
	labMaxInputTicksDisplay: TLabel;
	labMaxInputTicks: TLabel;
	labTicksWrittenDisplay: TLabel;
	labTicksWritten: TLabel;
	labQueueLengthDisplay: TLabel;
	labChartNumberLabel: TLabel;
	labChartNumberDisplay: TLabel;
	labDBHost: TLabel;
	labDBName: TLabel;
	labDBHostPort: TLabel;
	labDBUser: TLabel;
	labBrokerNumberLabel: TLabel;
	labBrokerNumberDisplay: TLabel;
	LabQueueLength: TLabel;
	labSettingFileDisplay: TLabel;
	labThreadNumberDisplay: TLabel;
	labThreadNumberLabel: TLabel;
	dlgOpenSettingFile: TOpenDialog;
	procedure btnOpenSettingFileClick(Sender: TObject);
	procedure FormCloseQuery(
                Sender: TObject;
		var CanClose: boolean);
private
	pgSettingFileName		: AnsiString;
        SettingsOK			: Boolean;
        QueueManager			: Pointer;
        // log a message to the debug monitor
	procedure Log(AMessage: WideString);
	procedure Log(AMessage: WideString; AArgs: array of const);
	{ private declarations }
public
        Config				: PQConfigClass;
	{ public declarations }
        constructor Create(AOwner: TComponent); override;
        destructor  Destroy; override;
end;

var
		frmWriterWindow: TfrmWriterWindow;

implementation
uses
        umt4_PQ_QueueManager;
{$R *.lfm}

{ TfrmWriterWindow }
constructor TfrmWriterWindow.Create(AOwner: TComponent);
begin
        config:=PQConfigClass.Create(
        	'',	// Broker timezone
                '',	// Machine time zone
                '',	// EA name
                '',	// Pair name
                '',	// Broker name
                1,	// is_Demo
                1,	// Timeframe (obsolete!)
                1,	// Point
                0,	// Digits
                100,	// Polling interval
                '',	// DB Host name
                5432,	// DB Host port
                '',	// DB Name
                '',	// DB User
                '',	// DB Password
                10	// Max retries

        );
        config.MaxCharts:=40;
        config.MaxBrokers:=10;
        config.MaxTicks:=1000;
        SettingsOK:=false;
        QueueManager:=NIL;
	inherited Create(AOwner);
end;

destructor  TfrmWriterWindow.Destroy;
begin
        if (QueueManager<>NIL) then begin
	        MT4PQueueManagerClass(QueueManager).destroy();
	end;
	inherited Destroy;
end;

procedure TfrmWriterWindow.btnOpenSettingFileClick(Sender: TObject);
begin

	if (dlgOpenSettingFile.Execute) then begin
		pgSettingFileName:=dlgOpenSettingFile.FileName;
                labSettingFileDisplay.Caption:='Using "' + pgSettingFileName + '"';
                if (config.ReadSettings(pgSettingFileName)) then begin
                        labDBHost.Caption:=config.DBHostname;
                        labDBHostPort.Caption:=Format('%d', [config.DBHostPort]);
                        labDBName.Caption:=config.DBName;
                        labDBUser.Caption:=config.DBUserName;
                        labThreadNumberDisplay.Caption:=Format('%d', [config.DBThreadCount]);
                        labChartNumberDisplay.Caption:=Format('%d', [config.MaxCharts]);
                        labBrokerNumberDisplay.Caption:=Format('%d', [config.MaxBrokers]);
                        labMaxTicksDisplay.Caption:=Format('%d', [config.MaxTicks]);
                        labMaxInputTicksDisplay.Caption:=Format('%d', [config.MaxBrokers*config.MaxCharts*config.MaxTicks]);
                	QueueManager:=MT4PQueueManagerClass.create(self);
		end;
	end;
end;

procedure TfrmWriterWindow.FormCloseQuery(Sender: TObject; var CanClose: boolean
		);
var
	Reply, BoxStyle: Integer;
begin
	BoxStyle := MB_ICONQUESTION + MB_YESNO;
  	Reply := Application.MessageBox('Do you really want to quit', 'Exit application', BoxStyle);
  	if Reply = IDYES then
                CanClose:=true
	else
                CanClose:=false;
end;


// log a message to the debug monitor
procedure TfrmWriterWindow.Log(AMessage: WideString);
begin
	OutputDebugStringW( PWideChar(AMessage) );
end;

// log a formatted message to the debug monitor
procedure TfrmWriterWindow.Log(AMessage: WideString; AArgs: array of const);
begin
	Log(Format(AMessage, AArgs));
end;

end.
