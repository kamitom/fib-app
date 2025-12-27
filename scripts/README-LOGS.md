# 腳本日誌系統說明

## 📝 日誌記錄功能

AWS 基礎設施腳本提供 **兩種執行方式**：

### 方式 1：不記錄日誌（快速模式）

```bash
./scripts/setup-aws-infrastructure.sh
./scripts/cleanup-aws-infrastructure.sh
```

- ✅ 互動式輸入正常運作
- ✅ 執行速度快
- ❌ 不記錄日誌

**適用於**：測試、學習、快速操作

### 方式 2：記錄日誌（安全模式）

```bash
./scripts/setup-aws-infrastructure-with-logging.sh
./scripts/cleanup-aws-infrastructure-with-logging.sh
```

- ✅ 互動式輸入正常運作
- ✅ 自動記錄並脫敏日誌
- ✅ 保留最近 10 個日誌
- ⚠️ 稍微增加執行時間（約 1-2 秒）

**適用於**：正式部署、審計需求、問題排查

### 日誌檔案位置

```
logs/
├── setup-20250127-143022.log      # 建立基礎設施日誌
├── cleanup-20250127-150315.log    # 清理資源日誌
└── ...
```

### 日誌檔名格式

- **建立腳本**: `setup-YYYYMMDD-HHMMSS.log`
- **清理腳本**: `cleanup-YYYYMMDD-HHMMSS.log`

時間戳記格式：`年月日-時分秒`

## 🔒 安全特性

### 自動脫敏處理

日誌系統會自動過濾以下敏感資訊：

1. **密碼** - 所有包含 `password`/`Password`/`PASSWORD` 的值
   ```
   原始: --master-user-password MySecretPass123
   記錄: --master-user-password ***REDACTED***
   ```

2. **AWS Access Key** - 格式 `AKIA...`
   ```
   原始: AKIAIOSFODNN7EXAMPLE
   記錄: ***REDACTED_ACCESS_KEY***
   ```

3. **AWS Secret Key** - 40 字元 base64 字串
   ```
   原始: wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
   記錄: ***REDACTED_SECRET***
   ```

### Git 防護

日誌目錄已加入 `.gitignore`，確保不會意外提交到版本控制：

```gitignore
# Logs
logs/
*.log
```

## 🗂️ 日誌保留策略

- **自動清理**：只保留最近 10 個日誌檔案
- **執行時機**：每次腳本執行完成時
- **清理邏輯**：
  ```bash
  # 保留最近 10 個 setup 日誌
  # 保留最近 10 個 cleanup 日誌
  ```

## 📊 日誌內容

### 記錄資訊

- ✅ 所有終端輸出（stdout + stderr）
- ✅ 執行時間戳記（開始/結束）
- ✅ AWS CLI 命令輸出
- ✅ 錯誤訊息和警告
- ✅ 資源建立/刪除狀態
- ❌ 敏感資訊（已自動脫敏）

### 日誌範例

```log
日誌記錄至: /path/to/logs/setup-20250127-143022.log
開始時間: Mon Jan 27 14:30:22 UTC 2025

================================================
Fib-App AWS Infrastructure Setup
================================================

請選擇要設置的環境：
  1) Staging
  2) Production

選擇 (1 或 2): 1

================================================
Step 1: 資料庫配置
================================================

PostgreSQL 主使用者名稱 [fib_staging]:
PostgreSQL 主密碼（至少 8 字元）: ***REDACTED***

✓ 配置完成

================================================
Step 2: 驗證 AWS 帳戶
================================================
✓ AWS Account ID: 123456789012
✓ AWS Region: ap-northeast-1

...

結束時間: Mon Jan 27 15:05:43 UTC 2025
完整日誌已儲存至: /path/to/logs/setup-20250127-143022.log
```

## 🔍 查看日誌

### 查看最新日誌

```bash
# 最新的 setup 日誌
tail -f logs/setup-*.log | tail -1

# 最新的 cleanup 日誌
tail -f logs/cleanup-*.log | tail -1
```

### 列出所有日誌

```bash
# 按時間排序（最新在上）
ls -lt logs/

# 只看 setup 日誌
ls -lt logs/setup-*.log

# 只看 cleanup 日誌
ls -lt logs/cleanup-*.log
```

### 搜尋特定資訊

```bash
# 搜尋錯誤訊息
grep -i error logs/setup-*.log

# 搜尋警告
grep -i warning logs/*.log

# 搜尋特定資源
grep "RDS Endpoint" logs/setup-*.log
```

## 🧹 手動清理日誌

### 刪除所有日誌

```bash
rm -rf logs/
```

### 刪除舊日誌（保留最近 5 個）

```bash
# Setup 日誌
ls -t logs/setup-*.log | tail -n +6 | xargs rm

# Cleanup 日誌
ls -t logs/cleanup-*.log | tail -n +6 | xargs rm
```

### 刪除特定日期的日誌

```bash
# 刪除 2025年1月的日誌
rm logs/*-202501*.log
```

## ⚠️ 重要提醒

1. **不要提交日誌到 Git**
   - 即使已脫敏，仍可能包含帳號資訊
   - 確認 `.gitignore` 包含 `logs/`

2. **敏感資訊保護**
   - 日誌已自動脫敏，但請定期檢查
   - 不要將日誌分享給未授權人員

3. **磁碟空間**
   - 定期檢查 `logs/` 目錄大小
   - 必要時手動清理舊日誌

4. **偵錯用途**
   - 當腳本失敗時，日誌是最好的偵錯工具
   - 包含完整的 AWS CLI 輸出和錯誤訊息

## 📋 常見問題

### Q: 日誌會洩露敏感資訊嗎？

A: 不會。所有密碼、Access Key、Secret Key 都會自動脫敏處理。

### Q: 為什麼有兩個版本的腳本？

A: 因為互動式輸入（`read` 命令）與自動日誌重定向會衝突。分離成兩個版本可以：
   - 快速模式：直接執行，不記錄日誌
   - 安全模式：使用 wrapper 腳本，記錄並脫敏日誌

### Q: 日誌會影響腳本執行速度嗎？

A: 使用 `-with-logging.sh` 版本會稍微增加 1-2 秒（用於脫敏處理）。

### Q: 哪個版本應該用於正式部署？

A: 建議使用 `-with-logging.sh` 版本，以便記錄完整的部署過程供審計和排錯。

## 🛡️ 最佳實踐

1. **執行前檢查**：確認 `logs/` 目錄不在 git 追蹤中
   ```bash
   git check-ignore logs/
   # 應輸出: logs/
   ```

2. **定期審查**：每月檢查日誌目錄大小
   ```bash
   du -sh logs/
   ```

3. **備份重要日誌**：成功部署後，可將日誌複製到安全位置
   ```bash
   cp logs/setup-20250127-*.log ~/backups/
   ```

4. **問題排查**：遇到錯誤時，先查看最新日誌
   ```bash
   less $(ls -t logs/*.log | head -1)
   ```
