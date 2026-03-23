# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

---

## プロジェクト概要

**indicator2EA** は、MetaTrader 4（MT4）のチャートに既に配置済みのサインインジケーターを、そのまま自動売買EA（Expert Advisor）へ変換するフレームワーク。バッファ型・オブジェクト型どちらのサインにも対応し、ほぼあらゆるインジケーターをEA化できることを目標とする。

**すべてのUI・コメント・ログ・input説明は日本語で記述すること。**

---

## 開発環境

- **言語**: MQL4（`.mq4`, `.mqh`）
- **IDE**: MetaEditor（MetaTrader 4付属）または VS Code + MQL拡張
- **コンパイル**: MetaEditorで `F7`、またはコマンドライン `metaeditor.exe /compile <file>`
- **テスト**: MetaTrader 4 Strategy Tester（バックテスト）、またはチャートへの直接アタッチ

---

## アーキテクチャ：2種類のシグナル検出方式

### 1. バッファ型（Buffer型）
インジケーターが `SetIndexBuffer()` で定義した数値バッファを `iCustom()` で読み取る方式。

```mql4
// 例：バッファ0がBuyサイン、バッファ1がSellサインのインジケーター
double buySignal  = iCustom(NULL, 0, "インジケーター名", /*params...,*/ 0, 1); // shift=1 (確定足)
double sellSignal = iCustom(NULL, 0, "インジケーター名", /*params...,*/ 1, 1);

bool isBuy  = (buySignal  != EMPTY_VALUE && buySignal  != 0);
bool isSell = (sellSignal != EMPTY_VALUE && sellSignal != 0);
```

**ポイント**:
- `EMPTY_VALUE`（=DBL_MAX）チェックが必須
- `shift=1`（1本前の確定足）でシグナルを取得するのが基本
- バッファ番号はインジケーターのソースで `SetIndexBuffer(番号, ...)` を確認する

### 2. オブジェクト型（Object型）
インジケーターがチャート上に `OBJ_ARROW` などのオブジェクトを配置する方式。`ObjectsTotal()` でスキャンして検出する。

```mql4
// 例：直近バーに配置されたArrowオブジェクトを検出
datetime barTime = iTime(NULL, 0, 1); // 直近確定足の時刻
for(int i = ObjectsTotal() - 1; i >= 0; i--) {
    string name = ObjectName(i);
    if(ObjectGetInteger(0, name, OBJPROP_TYPE) != OBJ_ARROW) continue;
    datetime objTime = (datetime)ObjectGetInteger(0, name, OBJPROP_TIME1);
    if(objTime != barTime) continue;

    int arrowCode = (int)ObjectGetInteger(0, name, OBJPROP_ARROWCODE);
    double arrowPrice = ObjectGetDouble(0, name, OBJPROP_PRICE1);
    color arrowColor  = (color)ObjectGetInteger(0, name, OBJPROP_COLOR);

    // 矢印の向き・色・コードでBuy/Sell判定
    if(arrowCode == 233 || arrowColor == clrBlue) { /* Buy */ }
    if(arrowCode == 234 || arrowColor == clrRed)  { /* Sell */ }
}
```

**ポイント**:
- `OBJPROP_ARROWCODE`: 上矢印=233、下矢印=234（インジケーター依存）
- `OBJPROP_COLOR`: 色でBuy/Sellを区別するインジケーターが多い
- オブジェクト名のプレフィックス（例: `"Signal_"`）でフィルタリングも有効

---

## EAの共通構成パターン

```
EA本体.mq4
├── input group "=== 基本設定 ==="
│   ├── マジックナンバー
│   └── シグナル検出方式（バッファ型/オブジェクト型）
├── input group "=== インジケーター設定 ==="
│   ├── インジケーター名（ファイルパス）
│   └── バッファ番号またはオブジェクト識別子
├── input group "=== 資金管理 ==="
│   ├── ロット計算方式（固定/リスク率）
│   ├── 損切り・利確（pips）
│   └── 最大ポジション数
├── input group "=== フィルター ==="
│   ├── 時間帯フィルター（JST基準）
│   └── 連続シグナル防止（バー数クールダウン）
└── input group "=== 通知設定 ==="
    ├── プッシュ通知
    └── LINE Notify
```

---

## シグナル検出の設計原則

1. **新規バー検出**: `iTime(NULL,0,0) != g_lastBarTime` で新バーのみ処理（ティック毎処理を避ける）
2. **確定足参照**: シグナルは `shift=1`（1本前）から取得して確定済みシグナルのみ使用
3. **重複エントリー防止**: 同一バーでの二重エントリーをグローバル変数で管理
4. **マジックナンバー**: EAごとに固有値を設定し、OrderSelect時に必ず照合する

---

## 既存コードの参照先

- Cursor履歴の `EA_MA_RSI` / `XAU_MA_RSI`（MQL5）— ニュースフィルター・LINE通知・リスク管理の実装パターン（MQL4へ移植する際の参考）

---

## コーディング規約

- **input変数**: `Inp` プレフィックス（例: `InpMagicNumber`, `InpRiskPercent`）
- **グローバル変数**: `g_` プレフィックス（例: `g_lastBarTime`）
- **ログ関数**: `void log(string msg)` を定義し、`Print("[EA名] ", msg)` 形式で出力
- **input説明文**: MT4のパラメーターダイアログに表示される `//` コメントは日本語で記載
- **エラーログ**: `GetLastError()` の結果を必ずログ出力する

