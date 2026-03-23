//+------------------------------------------------------------------+
//|                                               SignalMonitor.mq4 |
//|        サインインジケーターのシグナル検出テスト用EA               |
//|        バッファ型・オブジェクト型の両方式に対応                   |
//|        検出結果をExpertタブへ出力して動作確認を行う               |
//+------------------------------------------------------------------+
#property copyright "indicator2EA Project"
#property version   "1.00"
#property strict

//+------------------------------------------------------------------+
//| 検出方式の列挙                                                    |
//+------------------------------------------------------------------+
enum ENUM_SIGNAL_MODE
{
   MODE_BUFFER = 0,   // バッファ型（iCustomで読み取り）
   MODE_OBJECT = 1    // オブジェクト型（チャートオブジェクト走査）
};

//+------------------------------------------------------------------+
//| 入力パラメーター                                                  |
//+------------------------------------------------------------------+
input string            InpEALabel        = "SignalMonitor";   // EA表示名（ログ用）
input ENUM_SIGNAL_MODE  InpSignalMode     = MODE_BUFFER;       // シグナル検出方式

//--- バッファ型設定
input string InpIndicatorName  = "";     // インジケーター名（Indicators/以下のパス）
input string InpIndicatorParams = "";    // パラメーター（カンマ区切り 例: 14,20,1.5）
input int    InpBuyBufferIndex  = 0;     // Buyシグナルのバッファ番号
input int    InpSellBufferIndex = 1;     // Sellシグナルのバッファ番号
input int    InpCheckShift      = 1;     // 参照バー（0=現在足, 1=確定足）

//--- オブジェクト型設定
input string InpObjNameFilter   = "";    // オブジェクト名フィルター（空=全対象）
input int    InpBuyArrowCode    = 233;   // Buy矢印コード（233=上向き）
input int    InpSellArrowCode   = 234;   // Sell矢印コード（234=下向き）
input color  InpBuyArrowColor   = clrNONE;  // Buy矢印の色（clrNONE=色判定しない）
input color  InpSellArrowColor  = clrNONE;  // Sell矢印の色（clrNONE=色判定しない）

//--- 共通設定
input bool   InpEveryTick       = false; // 毎ティック監視（false=新規バーのみ）
input bool   InpScanAllBuffers  = false; // 全バッファ値を一括表示（デバッグ用）
input int    InpMaxBufferScan   = 8;     // 一括表示時の最大バッファ数

//+------------------------------------------------------------------+
//| グローバル変数                                                    |
//+------------------------------------------------------------------+
datetime g_lastBarTime = 0;
int      g_totalSignals = 0;

//+------------------------------------------------------------------+
//| 初期化                                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   log("====================================");
   log("シグナルモニター 起動");
   log("====================================");
   log("通貨ペア: " + Symbol() + " / 時間足: " + PeriodToStr(Period()));

   if(InpSignalMode == MODE_BUFFER)
   {
      log("検出方式: バッファ型");
      if(StringLen(InpIndicatorName) == 0)
      {
         log("警告: インジケーター名が未設定です。パラメーターを設定してください");
         log("　→ EAプロパティ → パラメーターの入力 → インジケーター名 を設定");
      }
      else
      {
         log("インジケーター: " + InpIndicatorName);
         log("パラメーター: " + (StringLen(InpIndicatorParams) > 0 ? InpIndicatorParams : "(なし)"));
         log("Buyバッファ: " + IntegerToString(InpBuyBufferIndex)
           + " / Sellバッファ: " + IntegerToString(InpSellBufferIndex));
         log("参照バー: " + IntegerToString(InpCheckShift)
           + (InpCheckShift == 0 ? "（現在足・未確定）" : "（確定足）"));

         // 初回読み取りテスト
         if(!TestBufferRead())
         {
            log("警告: 初回バッファ読み取りに失敗。インジケーター名・パラメーターを確認してください");
         }
      }
   }
   else
   {
      log("検出方式: オブジェクト型");
      log("名前フィルター: " + (StringLen(InpObjNameFilter) > 0 ? InpObjNameFilter : "(なし・全対象)"));
      log("Buy矢印コード: " + IntegerToString(InpBuyArrowCode)
        + " / Sell矢印コード: " + IntegerToString(InpSellArrowCode));
      if(InpBuyArrowColor != clrNONE)
         log("Buy矢印色: " + ColorToString(InpBuyArrowColor));
      if(InpSellArrowColor != clrNONE)
         log("Sell矢印色: " + ColorToString(InpSellArrowColor));

      // 初回オブジェクトスキャン
      int arrowCount = CountArrowObjects();
      log("チャート上のArrowオブジェクト数: " + IntegerToString(arrowCount));
   }

   log("監視モード: " + (InpEveryTick ? "毎ティック" : "新規バーのみ"));
   log("====================================");

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| 終了処理                                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   log("シグナルモニター 停止（検出シグナル合計: "
     + IntegerToString(g_totalSignals) + "）");
}

//+------------------------------------------------------------------+
//| ティック処理                                                      |
//+------------------------------------------------------------------+
void OnTick()
{
   // 新規バー判定
   if(!InpEveryTick)
   {
      datetime currentBarTime = iTime(NULL, 0, 0);
      if(currentBarTime == g_lastBarTime)
         return;
      g_lastBarTime = currentBarTime;
   }

   // 方式別にシグナル検出
   if(InpSignalMode == MODE_BUFFER)
   {
      if(StringLen(InpIndicatorName) == 0) return; // 未設定なら何もしない
      CheckBufferSignals();
   }
   else
      CheckObjectSignals();
}

//+------------------------------------------------------------------+
//| バッファ型：初回読み取りテスト                                    |
//+------------------------------------------------------------------+
bool TestBufferRead()
{
   double val = ReadBuffer(InpBuyBufferIndex, InpCheckShift);
   int err = GetLastError();
   if(err != 0)
   {
      log("iCustom呼び出しエラー: " + IntegerToString(err));
      return false;
   }

   log("初回テスト読み取り成功 — バッファ" + IntegerToString(InpBuyBufferIndex)
     + "[shift=" + IntegerToString(InpCheckShift) + "] = " + DoubleToString(val, 5));
   return true;
}

//+------------------------------------------------------------------+
//| バッファ型：シグナル検出                                          |
//+------------------------------------------------------------------+
void CheckBufferSignals()
{
   // 全バッファ一括表示モード
   if(InpScanAllBuffers)
   {
      ScanAllBuffers();
      return;
   }

   double buyVal  = ReadBuffer(InpBuyBufferIndex, InpCheckShift);
   double sellVal = ReadBuffer(InpSellBufferIndex, InpCheckShift);

   bool isBuy  = IsValidSignal(buyVal);
   bool isSell = IsValidSignal(sellVal);

   if(isBuy)
   {
      g_totalSignals++;
      log("★ BUYシグナル検出 | バッファ[" + IntegerToString(InpBuyBufferIndex) + "]="
        + DoubleToString(buyVal, 5)
        + " | バー時刻: " + TimeToString(iTime(NULL, 0, InpCheckShift))
        + " | 検出#" + IntegerToString(g_totalSignals));
   }

   if(isSell)
   {
      g_totalSignals++;
      log("★ SELLシグナル検出 | バッファ[" + IntegerToString(InpSellBufferIndex) + "]="
        + DoubleToString(sellVal, 5)
        + " | バー時刻: " + TimeToString(iTime(NULL, 0, InpCheckShift))
        + " | 検出#" + IntegerToString(g_totalSignals));
   }
}

//+------------------------------------------------------------------+
//| バッファ型：全バッファ一括スキャン（デバッグ用）                  |
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

      line += "[" + IntegerToString(i) + "]=" + valStr + " ";
   }

   // 値のあるバッファが存在する場合のみ出力（ログを見やすくするため）
   if(hasSignal)
      log(line);
}

//+------------------------------------------------------------------+
//| バッファ型：iCustom呼び出し                                       |
//| パラメーター文字列をパースして各型に対応                          |
//+------------------------------------------------------------------+
double ReadBuffer(int bufferIndex, int shift)
{
   // パラメーターなしの場合
   if(StringLen(InpIndicatorParams) == 0)
      return iCustom(NULL, 0, InpIndicatorName, bufferIndex, shift);

   // カンマ区切りパラメーターをパースして呼び出し
   // MQL4のiCustomは可変引数のため、パラメーター数に応じた呼び出しが必要
   string params[];
   int count = StringSplitByComma(InpIndicatorParams, params);

   // パラメーター数に応じてiCustomを呼び分け（MQL4は可変引数を動的に渡せないため）
   if(count == 1)
      return iCustom(NULL, 0, InpIndicatorName,
               ParseParam(params[0]),
               bufferIndex, shift);
   if(count == 2)
      return iCustom(NULL, 0, InpIndicatorName,
               ParseParam(params[0]), ParseParam(params[1]),
               bufferIndex, shift);
   if(count == 3)
      return iCustom(NULL, 0, InpIndicatorName,
               ParseParam(params[0]), ParseParam(params[1]),
               ParseParam(params[2]),
               bufferIndex, shift);
   if(count == 4)
      return iCustom(NULL, 0, InpIndicatorName,
               ParseParam(params[0]), ParseParam(params[1]),
               ParseParam(params[2]), ParseParam(params[3]),
               bufferIndex, shift);
   if(count == 5)
      return iCustom(NULL, 0, InpIndicatorName,
               ParseParam(params[0]), ParseParam(params[1]),
               ParseParam(params[2]), ParseParam(params[3]),
               ParseParam(params[4]),
               bufferIndex, shift);
   if(count == 6)
      return iCustom(NULL, 0, InpIndicatorName,
               ParseParam(params[0]), ParseParam(params[1]),
               ParseParam(params[2]), ParseParam(params[3]),
               ParseParam(params[4]), ParseParam(params[5]),
               bufferIndex, shift);
   if(count == 7)
      return iCustom(NULL, 0, InpIndicatorName,
               ParseParam(params[0]), ParseParam(params[1]),
               ParseParam(params[2]), ParseParam(params[3]),
               ParseParam(params[4]), ParseParam(params[5]),
               ParseParam(params[6]),
               bufferIndex, shift);
   if(count == 8)
      return iCustom(NULL, 0, InpIndicatorName,
               ParseParam(params[0]), ParseParam(params[1]),
               ParseParam(params[2]), ParseParam(params[3]),
               ParseParam(params[4]), ParseParam(params[5]),
               ParseParam(params[6]), ParseParam(params[7]),
               bufferIndex, shift);

   log("警告: パラメーター数が多すぎます（最大8）。パラメーターなしで実行します");
   return iCustom(NULL, 0, InpIndicatorName, bufferIndex, shift);
}

//+------------------------------------------------------------------+
//| オブジェクト型：シグナル検出                                      |
//+------------------------------------------------------------------+
void CheckObjectSignals()
{
   datetime targetTime = iTime(NULL, 0, InpCheckShift);
   int total = ObjectsTotal();

   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(i);

      // オブジェクトタイプがArrowであること
      if(ObjectType(name) != OBJ_ARROW)
         continue;

      // 名前フィルター
      if(StringLen(InpObjNameFilter) > 0)
      {
         if(StringFind(name, InpObjNameFilter) < 0)
            continue;
      }

      // 対象バーの時刻と一致するか
      datetime objTime = (datetime)ObjectGet(name, OBJPROP_TIME1);
      if(objTime != targetTime)
         continue;

      // 矢印のプロパティ取得
      int    arrowCode  = (int)ObjectGet(name, OBJPROP_ARROWCODE);
      double arrowPrice = ObjectGet(name, OBJPROP_PRICE1);
      color  arrowColor = (color)ObjectGet(name, OBJPROP_COLOR);

      // Buy/Sell判定
      string direction = JudgeObjectDirection(arrowCode, arrowColor);

      g_totalSignals++;
      log("★ " + direction + "シグナル検出（オブジェクト型）"
        + " | 名前: " + name
        + " | コード: " + IntegerToString(arrowCode)
        + " | 色: " + ColorToString(arrowColor)
        + " | 価格: " + DoubleToString(arrowPrice, (int)MarketInfo(Symbol(), MODE_DIGITS))
        + " | バー時刻: " + TimeToString(objTime)
        + " | 検出#" + IntegerToString(g_totalSignals));
   }
}

//+------------------------------------------------------------------+
//| オブジェクト型：矢印の方向判定                                    |
//+------------------------------------------------------------------+
string JudgeObjectDirection(int arrowCode, color arrowColor)
{
   // 色による判定（設定されている場合に優先）
   if(InpBuyArrowColor != clrNONE && arrowColor == InpBuyArrowColor)
      return "BUY";
   if(InpSellArrowColor != clrNONE && arrowColor == InpSellArrowColor)
      return "SELL";

   // 矢印コードによる判定
   if(arrowCode == InpBuyArrowCode)
      return "BUY";
   if(arrowCode == InpSellArrowCode)
      return "SELL";

   return "不明(" + IntegerToString(arrowCode) + ")";
}

//+------------------------------------------------------------------+
//| オブジェクト型：Arrowオブジェクト数のカウント                     |
//+------------------------------------------------------------------+
int CountArrowObjects()
{
   int count = 0;
   int total = ObjectsTotal();
   for(int i = 0; i < total; i++)
   {
      if(ObjectType(ObjectName(i)) == OBJ_ARROW)
         count++;
   }
   return count;
}

//+------------------------------------------------------------------+
//| ユーティリティ：シグナル値の有効判定                              |
//+------------------------------------------------------------------+
bool IsValidSignal(double value)
{
   if(value == EMPTY_VALUE)  return false;
   if(value >= DBL_MAX - 1)  return false;
   if(value == 0.0)          return false;
   return true;
}

//+------------------------------------------------------------------+
//| ユーティリティ：パラメーター文字列→double変換                    |
//+------------------------------------------------------------------+
double ParseParam(string s)
{
   StringTrimLeft(s);
   StringTrimRight(s);
   return StringToDouble(s);
}

//+------------------------------------------------------------------+
//| ユーティリティ：カンマ区切り文字列の分割                          |
//+------------------------------------------------------------------+
int StringSplitByComma(string text, string &result[])
{
   int count = 0;
   string remaining = text;

   while(StringLen(remaining) > 0)
   {
      int pos = StringFind(remaining, ",");
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
//| ユーティリティ：時間足を文字列に変換                              |
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
//| ユーティリティ：ログ出力                                          |
//+------------------------------------------------------------------+
void log(string msg)
{
   Print("[" + InpEALabel + "] " + msg);
}
//+------------------------------------------------------------------+
