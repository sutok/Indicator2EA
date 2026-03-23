//+------------------------------------------------------------------+
//|                                               SignalMonitor.mq4 |
//|        サインインジケーターのシグナル検出テスト用EA               |
//|        バッファ型・オブジェクト型の両方式に対応                   |
//|        検出結果をExpertタブへ出力して動作確認を行う               |
//+------------------------------------------------------------------+
#property copyright "indicator2EA Project"
#property version   "1.02"
#property strict

//+------------------------------------------------------------------+
//| 検出方式の列挙                                                    |
//+------------------------------------------------------------------+
enum ENUM_SIGNAL_MODE
{
   MODE_BUFFER = 0,   // バッファ型(iCustomで読み取り)
   MODE_OBJECT = 1    // オブジェクト型(チャートオブジェクト走査)
};

//+------------------------------------------------------------------+
//| 入力パラメーター                                                  |
//+------------------------------------------------------------------+
input string            InpEALabel        = "SignalMonitor";   // EA表示名(ログ用)
input ENUM_SIGNAL_MODE  InpSignalMode     = MODE_BUFFER;       // シグナル検出方式

//--- バッファ型設定
input string InpIndicatorName   = "";     // インジケーター名(Indicators以下のパス)
input string InpIndicatorParams = "";     // パラメーター(カンマ区切り 例: 14,20,1.5)
input int    InpBuyBufferIndex  = 0;      // Buyシグナルのバッファ番号
input int    InpSellBufferIndex = 1;      // Sellシグナルのバッファ番号
input int    InpCheckShift      = 1;      // 参照バー(0=現在足, 1=確定足)

//--- オブジェクト型設定
input string InpObjNameFilter   = "";     // オブジェクト名フィルター(空=全対象)
input int    InpBuyArrowCode    = 233;    // Buy矢印コード(233=上向き)
input int    InpSellArrowCode   = 234;    // Sell矢印コード(234=下向き)
input color  InpBuyArrowColor   = clrNONE;  // Buy矢印の色(clrNONE=色判定しない)
input color  InpSellArrowColor  = clrNONE;  // Sell矢印の色(clrNONE=色判定しない)

//--- 共通設定
input bool   InpEveryTick       = false;  // 毎ティック監視(false=新規バーのみ)
input bool   InpScanAllBuffers  = false;  // 全バッファ値を一括表示(デバッグ用)
input int    InpMaxBufferScan   = 8;      // 一括表示時の最大バッファ数

//+------------------------------------------------------------------+
//| グローバル変数                                                    |
//+------------------------------------------------------------------+
datetime g_lastBarTime    = 0;
int      g_totalSignals   = 0;
bool     g_initialized    = false;  // 初回ティックで設定情報を表示済みか

//+------------------------------------------------------------------+
//| 初期化 - 最小限にとどめ、外部リソースへのアクセスは行わない       |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("[", InpEALabel, "] シグナルモニター 起動");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| 終了処理                                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("[", InpEALabel, "] シグナルモニター 停止 (検出シグナル合計: ",
         g_totalSignals, " / 終了理由: ", reason, ")");
}

//+------------------------------------------------------------------+
//| ティック処理                                                      |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- 初回ティックで設定情報を表示
   if(!g_initialized)
   {
      PrintSettings();
      g_initialized = true;
   }

   //--- 新規バー判定
   if(!InpEveryTick)
   {
      datetime currentBarTime = iTime(NULL, 0, 0);
      if(currentBarTime == g_lastBarTime)
         return;
      g_lastBarTime = currentBarTime;
   }

   //--- 方式別にシグナル検出
   if(InpSignalMode == MODE_BUFFER)
   {
      if(StringLen(InpIndicatorName) == 0) return;
      CheckBufferSignals();
   }
   else
   {
      CheckObjectSignals();
   }
}

//+------------------------------------------------------------------+
//| 設定情報の表示(初回ティック時に実行)                              |
//+------------------------------------------------------------------+
void PrintSettings()
{
   Print("[", InpEALabel, "] ====================================");
   Print("[", InpEALabel, "] 通貨ペア: ", Symbol(), " / 時間足: ", PeriodToStr(Period()));

   if(InpSignalMode == MODE_BUFFER)
   {
      Print("[", InpEALabel, "] 検出方式: バッファ型");
      if(StringLen(InpIndicatorName) == 0)
      {
         Print("[", InpEALabel, "] 警告: インジケーター名が未設定です");
      }
      else
      {
         Print("[", InpEALabel, "] インジケーター: ", InpIndicatorName);
         Print("[", InpEALabel, "] パラメーター: ",
               (StringLen(InpIndicatorParams) > 0 ? InpIndicatorParams : "(なし)"));
         Print("[", InpEALabel, "] Buyバッファ: ", InpBuyBufferIndex,
               " / Sellバッファ: ", InpSellBufferIndex);
         Print("[", InpEALabel, "] 参照バー: ", InpCheckShift,
               (InpCheckShift == 0 ? " (現在足)" : " (確定足)"));
      }
   }
   else
   {
      Print("[", InpEALabel, "] 検出方式: オブジェクト型");
      Print("[", InpEALabel, "] 名前フィルター: ",
            (StringLen(InpObjNameFilter) > 0 ? InpObjNameFilter : "(なし/全対象)"));
      Print("[", InpEALabel, "] Buy矢印コード: ", InpBuyArrowCode,
            " / Sell矢印コード: ", InpSellArrowCode);
   }

   Print("[", InpEALabel, "] 監視モード: ", (InpEveryTick ? "毎ティック" : "新規バーのみ"));
   Print("[", InpEALabel, "] ====================================");
}

//+------------------------------------------------------------------+
//| バッファ型: シグナル検出                                          |
//+------------------------------------------------------------------+
void CheckBufferSignals()
{
   //--- 全バッファ一括表示モード
   if(InpScanAllBuffers)
   {
      ScanAllBuffers();
      return;
   }

   double buyVal  = ReadBuffer(InpBuyBufferIndex, InpCheckShift);
   double sellVal = ReadBuffer(InpSellBufferIndex, InpCheckShift);

   if(IsValidSignal(buyVal))
   {
      g_totalSignals++;
      Print("[", InpEALabel, "] * BUYシグナル検出 | バッファ[", InpBuyBufferIndex, "]=",
            DoubleToString(buyVal, 5),
            " | バー時刻: ", TimeToString(iTime(NULL, 0, InpCheckShift)),
            " | 検出#", g_totalSignals);
   }

   if(IsValidSignal(sellVal))
   {
      g_totalSignals++;
      Print("[", InpEALabel, "] * SELLシグナル検出 | バッファ[", InpSellBufferIndex, "]=",
            DoubleToString(sellVal, 5),
            " | バー時刻: ", TimeToString(iTime(NULL, 0, InpCheckShift)),
            " | 検出#", g_totalSignals);
   }
}

//+------------------------------------------------------------------+
//| バッファ型: 全バッファ一括スキャン(デバッグ用)                    |
//+------------------------------------------------------------------+
void ScanAllBuffers()
{
   string line = "全バッファ [shift=" + IntegerToString(InpCheckShift) + "]: ";
   bool hasSignal = false;

   for(int i = 0; i < InpMaxBufferScan; i++)
   {
      double val = ReadBuffer(i, InpCheckShift);
      string valStr;

      if(val == EMPTY_VALUE || val >= DBL_MAX - 1)
         valStr = "EMPTY";
      else if(val == 0.0)
         valStr = "0";
      else
      {
         valStr = DoubleToString(val, 5);
         hasSignal = true;
      }

      line = line + "[" + IntegerToString(i) + "]=" + valStr + " ";
   }

   if(hasSignal)
      Print("[", InpEALabel, "] ", line);
}

//+------------------------------------------------------------------+
//| バッファ型: iCustom呼び出し                                       |
//| パラメーター文字列をパースして各型に対応                          |
//+------------------------------------------------------------------+
double ReadBuffer(int bufferIndex, int shift)
{
   if(StringLen(InpIndicatorParams) == 0)
      return iCustom(NULL, 0, InpIndicatorName, bufferIndex, shift);

   string params[];
   int count = SplitString(InpIndicatorParams, ",", params);

   if(count == 1)
      return iCustom(NULL, 0, InpIndicatorName,
               ToDouble(params[0]),
               bufferIndex, shift);
   if(count == 2)
      return iCustom(NULL, 0, InpIndicatorName,
               ToDouble(params[0]), ToDouble(params[1]),
               bufferIndex, shift);
   if(count == 3)
      return iCustom(NULL, 0, InpIndicatorName,
               ToDouble(params[0]), ToDouble(params[1]),
               ToDouble(params[2]),
               bufferIndex, shift);
   if(count == 4)
      return iCustom(NULL, 0, InpIndicatorName,
               ToDouble(params[0]), ToDouble(params[1]),
               ToDouble(params[2]), ToDouble(params[3]),
               bufferIndex, shift);
   if(count == 5)
      return iCustom(NULL, 0, InpIndicatorName,
               ToDouble(params[0]), ToDouble(params[1]),
               ToDouble(params[2]), ToDouble(params[3]),
               ToDouble(params[4]),
               bufferIndex, shift);
   if(count == 6)
      return iCustom(NULL, 0, InpIndicatorName,
               ToDouble(params[0]), ToDouble(params[1]),
               ToDouble(params[2]), ToDouble(params[3]),
               ToDouble(params[4]), ToDouble(params[5]),
               bufferIndex, shift);
   if(count == 7)
      return iCustom(NULL, 0, InpIndicatorName,
               ToDouble(params[0]), ToDouble(params[1]),
               ToDouble(params[2]), ToDouble(params[3]),
               ToDouble(params[4]), ToDouble(params[5]),
               ToDouble(params[6]),
               bufferIndex, shift);
   if(count == 8)
      return iCustom(NULL, 0, InpIndicatorName,
               ToDouble(params[0]), ToDouble(params[1]),
               ToDouble(params[2]), ToDouble(params[3]),
               ToDouble(params[4]), ToDouble(params[5]),
               ToDouble(params[6]), ToDouble(params[7]),
               bufferIndex, shift);

   return iCustom(NULL, 0, InpIndicatorName, bufferIndex, shift);
}

//+------------------------------------------------------------------+
//| オブジェクト型: シグナル検出                                      |
//+------------------------------------------------------------------+
void CheckObjectSignals()
{
   datetime targetTime = iTime(NULL, 0, InpCheckShift);
   int total = ObjectsTotal();

   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(i);

      if(ObjectType(name) != OBJ_ARROW)
         continue;

      if(StringLen(InpObjNameFilter) > 0)
      {
         if(StringFind(name, InpObjNameFilter) < 0)
            continue;
      }

      datetime objTime = (datetime)ObjectGet(name, OBJPROP_TIME1);
      if(objTime != targetTime)
         continue;

      int    arrowCode  = (int)ObjectGet(name, OBJPROP_ARROWCODE);
      double arrowPrice = ObjectGet(name, OBJPROP_PRICE1);
      color  arrowColor = (color)ObjectGet(name, OBJPROP_COLOR);

      string direction = JudgeDirection(arrowCode, arrowColor);

      g_totalSignals++;
      Print("[", InpEALabel, "] * ", direction, "シグナル検出(オブジェクト型)",
            " | 名前: ", name,
            " | コード: ", arrowCode,
            " | 色: ", ColorToString(arrowColor),
            " | 価格: ", DoubleToString(arrowPrice, (int)MarketInfo(Symbol(), MODE_DIGITS)),
            " | バー時刻: ", TimeToString(objTime),
            " | 検出#", g_totalSignals);
   }
}

//+------------------------------------------------------------------+
//| オブジェクト型: 矢印の方向判定                                    |
//+------------------------------------------------------------------+
string JudgeDirection(int arrowCode, color arrowColor)
{
   if(InpBuyArrowColor  != clrNONE && arrowColor == InpBuyArrowColor)  return "BUY";
   if(InpSellArrowColor != clrNONE && arrowColor == InpSellArrowColor) return "SELL";
   if(arrowCode == InpBuyArrowCode)  return "BUY";
   if(arrowCode == InpSellArrowCode) return "SELL";
   return "不明(code=" + IntegerToString(arrowCode) + ")";
}

//+------------------------------------------------------------------+
//| シグナル値の有効判定                                              |
//+------------------------------------------------------------------+
bool IsValidSignal(double value)
{
   if(value == EMPTY_VALUE) return false;
   if(value >= DBL_MAX - 1) return false;
   if(value == 0.0)         return false;
   return true;
}

//+------------------------------------------------------------------+
//| 文字列をdoubleに変換(前後の空白除去付き)                         |
//+------------------------------------------------------------------+
double ToDouble(string s)
{
   StringTrimLeft(s);
   StringTrimRight(s);
   return StringToDouble(s);
}

//+------------------------------------------------------------------+
//| カンマ区切り文字列の分割                                          |
//+------------------------------------------------------------------+
int SplitString(string text, string delimiter, string &result[])
{
   int count = 0;
   string remaining = text;

   while(StringLen(remaining) > 0)
   {
      int pos = StringFind(remaining, delimiter);
      ArrayResize(result, count + 1);

      if(pos < 0)
      {
         result[count] = remaining;
         count++;
         break;
      }

      result[count] = StringSubstr(remaining, 0, pos);
      remaining = StringSubstr(remaining, pos + 1);
      count++;
   }

   return count;
}

//+------------------------------------------------------------------+
//| 時間足を文字列に変換                                              |
//+------------------------------------------------------------------+
string PeriodToStr(int period)
{
   switch(period)
   {
      case PERIOD_M1:  return "M1";
      case PERIOD_M5:  return "M5";
      case PERIOD_M15: return "M15";
      case PERIOD_M30: return "M30";
      case PERIOD_H1:  return "H1";
      case PERIOD_H4:  return "H4";
      case PERIOD_D1:  return "D1";
      case PERIOD_W1:  return "W1";
      case PERIOD_MN1: return "MN1";
      default:         return "M" + IntegerToString(period);
   }
}
//+------------------------------------------------------------------+
