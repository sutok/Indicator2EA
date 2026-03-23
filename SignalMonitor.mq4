//+------------------------------------------------------------------+
//|                                               SignalMonitor.mq4 |
//|        サインインジケーターのシグナル検出テスト用EA               |
//|        バッファ型・オブジェクト型を同時スキャンし全情報をログ出力 |
//+------------------------------------------------------------------+
#property copyright "indicator2EA Project"
#property version   "2.00"
#property strict

//+------------------------------------------------------------------+
//| 入力パラメーター                                                  |
//+------------------------------------------------------------------+
input string InpEALabel         = "SignalMonitor";   // EA表示名(ログ用)

//--- バッファ型設定
input string InpIndicatorName   = "";     // インジケーター名(Indicators以下のパス, 空=バッファ型スキップ)
input string InpIndicatorParams = "";     // パラメーター(カンマ区切り 例: 14,20,1.5)
input int    InpMaxBufferScan   = 8;      // スキャンするバッファ数(0-7なら8)

//--- 共通設定
input int    InpCheckShift      = 1;      // 参照バー(0=現在足, 1=確定足)
input bool   InpEveryTick       = false;  // 毎ティック監視(false=新規バーのみ)
input int    InpObjScanBars     = 5;      // オブジェクト型: 直近何本のバーを走査するか

//+------------------------------------------------------------------+
//| グローバル変数                                                    |
//+------------------------------------------------------------------+
datetime g_lastBarTime  = 0;
bool     g_initialized  = false;
int      g_prevObjTotal = 0;   // 前回のオブジェクト数(増減検知用)

//+------------------------------------------------------------------+
//| 初期化                                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("[", InpEALabel, "] シグナルモニター v2.00 起動");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| 終了処理                                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("[", InpEALabel, "] シグナルモニター 停止 (終了理由: ", reason, ")");
}

//+------------------------------------------------------------------+
//| ティック処理                                                      |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- 初回ティックで設定情報と現状スナップショットを表示
   if(!g_initialized)
   {
      PrintSettings();
      PrintSnapshot();
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

   //--- バッファ型スキャン
   if(StringLen(InpIndicatorName) > 0)
      ScanBuffers();

   //--- オブジェクト型スキャン
   ScanObjects();
}

//+------------------------------------------------------------------+
//| 設定情報の表示                                                    |
//+------------------------------------------------------------------+
void PrintSettings()
{
   Print("[", InpEALabel, "] ====================================");
   Print("[", InpEALabel, "] 通貨ペア: ", Symbol(), " / 時間足: ", PeriodToStr(Period()));
   Print("[", InpEALabel, "] 参照バー: shift=", InpCheckShift);
   Print("[", InpEALabel, "] 監視モード: ", (InpEveryTick ? "毎ティック" : "新規バーのみ"));

   if(StringLen(InpIndicatorName) > 0)
   {
      Print("[", InpEALabel, "] [バッファ型] インジケーター: ", InpIndicatorName);
      Print("[", InpEALabel, "] [バッファ型] パラメーター: ",
            (StringLen(InpIndicatorParams) > 0 ? InpIndicatorParams : "(なし)"));
      Print("[", InpEALabel, "] [バッファ型] スキャン範囲: バッファ0-", InpMaxBufferScan - 1);
   }
   else
   {
      Print("[", InpEALabel, "] [バッファ型] スキップ(インジケーター名未設定)");
   }

   Print("[", InpEALabel, "] [オブジェクト型] 常時スキャン有効 (直近", InpObjScanBars, "本)");
   Print("[", InpEALabel, "] ====================================");
}

//+------------------------------------------------------------------+
//| 初回スナップショット: 現在のチャート上の全情報をダンプ            |
//+------------------------------------------------------------------+
void PrintSnapshot()
{
   Print("[", InpEALabel, "] --- 初回スナップショット開始 ---");

   //--- バッファ型: 全バッファの現在値を表示
   if(StringLen(InpIndicatorName) > 0)
   {
      Print("[", InpEALabel, "] [バッファ] shift=", InpCheckShift, " の全バッファ値:");
      for(int i = 0; i < InpMaxBufferScan; i++)
      {
         double val = ReadBuffer(i, InpCheckShift);
         string status;
         if(val == EMPTY_VALUE || val >= DBL_MAX - 1)
            status = "EMPTY";
         else if(val == 0.0)
            status = "0 (空の可能性)";
         else
            status = DoubleToString(val, 5) + " << 値あり";

         Print("[", InpEALabel, "]   バッファ[", i, "] = ", status);
      }
   }

   //--- オブジェクト型: チャート上の全Arrowオブジェクトをダンプ
   int total = ObjectsTotal();
   int arrowCount = 0;
   Print("[", InpEALabel, "] [オブジェクト] チャート上の総オブジェクト数: ", total);

   for(int i = 0; i < total; i++)
   {
      string name = ObjectName(i);
      int objType = ObjectType(name);

      // Arrow以外もタイプ名だけ記録
      if(objType != OBJ_ARROW)
         continue;

      arrowCount++;
      datetime objTime   = (datetime)ObjectGet(name, OBJPROP_TIME1);
      double   objPrice  = ObjectGet(name, OBJPROP_PRICE1);
      int      arrowCode = (int)ObjectGet(name, OBJPROP_ARROWCODE);
      color    objColor  = (color)ObjectGet(name, OBJPROP_COLOR);
      int      objWidth  = (int)ObjectGet(name, OBJPROP_WIDTH);

      Print("[", InpEALabel, "]   Arrow #", arrowCount,
            " | 名前: ", name,
            " | 時刻: ", TimeToString(objTime),
            " | 価格: ", DoubleToString(objPrice, (int)MarketInfo(Symbol(), MODE_DIGITS)),
            " | コード: ", arrowCode, " (", ArrowCodeToStr(arrowCode), ")",
            " | 色: ", ColorToString(objColor),
            " | 太さ: ", objWidth);
   }

   Print("[", InpEALabel, "] [オブジェクト] Arrowオブジェクト合計: ", arrowCount);
   g_prevObjTotal = total;
   Print("[", InpEALabel, "] --- 初回スナップショット終了 ---");
}

//+------------------------------------------------------------------+
//| バッファ型: 全バッファスキャン(新規バー毎)                        |
//+------------------------------------------------------------------+
void ScanBuffers()
{
   string line = "";
   bool hasValue = false;

   for(int i = 0; i < InpMaxBufferScan; i++)
   {
      double val = ReadBuffer(i, InpCheckShift);

      if(val != EMPTY_VALUE && val < DBL_MAX - 1 && val != 0.0)
      {
         if(hasValue) line = line + " | ";
         line = line + "[" + IntegerToString(i) + "]=" + DoubleToString(val, 5);
         hasValue = true;
      }
   }

   if(hasValue)
   {
      Print("[", InpEALabel, "] [バッファ] shift=", InpCheckShift,
            " 時刻=", TimeToString(iTime(NULL, 0, InpCheckShift)),
            " => ", line);
   }
}

//+------------------------------------------------------------------+
//| オブジェクト型: 直近バーに紐づくArrowを全てダンプ                 |
//+------------------------------------------------------------------+
void ScanObjects()
{
   int total = ObjectsTotal();

   // オブジェクト数に変化がなければスキップ(負荷軽減)
   if(total == g_prevObjTotal)
      return;

   // 増えた場合のみ新しいオブジェクトをスキャン
   int diff = total - g_prevObjTotal;
   g_prevObjTotal = total;

   if(diff <= 0)
   {
      // 減った場合はカウントだけ更新
      return;
   }

   // 直近N本のバー時刻を取得
   datetime barTimes[];
   ArrayResize(barTimes, InpObjScanBars);
   for(int b = 0; b < InpObjScanBars; b++)
      barTimes[b] = iTime(NULL, 0, b);

   // 全Arrowオブジェクトから直近バーに紐づくものを出力
   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(i);
      if(ObjectType(name) != OBJ_ARROW)
         continue;

      datetime objTime = (datetime)ObjectGet(name, OBJPROP_TIME1);

      // 直近N本のバーに含まれるか
      bool isRecent = false;
      for(int b = 0; b < InpObjScanBars; b++)
      {
         if(objTime == barTimes[b])
         {
            isRecent = true;
            break;
         }
      }
      if(!isRecent) continue;

      int    arrowCode = (int)ObjectGet(name, OBJPROP_ARROWCODE);
      double objPrice  = ObjectGet(name, OBJPROP_PRICE1);
      color  objColor  = (color)ObjectGet(name, OBJPROP_COLOR);
      int    objWidth  = (int)ObjectGet(name, OBJPROP_WIDTH);

      Print("[", InpEALabel, "] [オブジェクト] 新規Arrow検出",
            " | 名前: ", name,
            " | 時刻: ", TimeToString(objTime),
            " | 価格: ", DoubleToString(objPrice, (int)MarketInfo(Symbol(), MODE_DIGITS)),
            " | コード: ", arrowCode, " (", ArrowCodeToStr(arrowCode), ")",
            " | 色: ", ColorToString(objColor),
            " | 太さ: ", objWidth);
   }
}

//+------------------------------------------------------------------+
//| バッファ型: iCustom呼び出し                                       |
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
//| 矢印コードの説明文字列                                            |
//+------------------------------------------------------------------+
string ArrowCodeToStr(int code)
{
   switch(code)
   {
      case 233: return "上矢印";
      case 234: return "下矢印";
      case 159: return "丸上矢印";
      case 160: return "丸下矢印";
      case 161: return "チェック";
      case 251: return "上向き三角";
      case 252: return "下向き三角";
      case 164: return "星";
      case 174: return "ダイヤ上";
      case 175: return "ダイヤ下";
      default:  return "Wingdings:" + IntegerToString(code);
   }
}

//+------------------------------------------------------------------+
//| 文字列をdoubleに変換                                              |
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
