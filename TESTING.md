# 測試文件

## 測試覆蓋範圍

### 1. 後端 (FastAPI) - 15 個測試
**檔案**: `fib-be/test_main.py`

- ✅ 基礎端點 (2 tests)
  - `GET /` - Root endpoint
  - `GET /health` - Health check

- ✅ 查詢索引 (2 tests)
  - `GET /values/all` - 空資料 & 有資料

- ✅ 查詢計算值 (2 tests)
  - `GET /values/current` - 空資料 & 有資料

- ✅ 提交索引 (8 tests)
  - 有效索引 (0, 10, 40)
  - 負數拒絕
  - 超過 40 拒絕
  - 無效 payload
  - 錯誤類型

- ✅ 重複索引處理 (1 test)

**執行**:
```bash
cd fib-be
pip install -r requirements.txt
pytest test_main.py -v
```

---

### 2. Worker (Node.js) - 13 個測試
**檔案**: `fib-worker/fib.test.js`

- ✅ 基礎情況 (2 tests)
  - fib(0) = 1
  - fib(1) = 1

- ✅ 小索引 (5 tests)
  - fib(2) 到 fib(6)

- ✅ 大索引 (3 tests)
  - fib(10), fib(15), fib(20)

- ✅ 最大索引 (1 test)
  - fib(40) = 165580141

- ✅ 邊界情況 (1 test)
  - 負數行為

- ✅ 效能測試 (1 test)
  - fib(40) < 10ms

**執行**:
```bash
cd fib-worker
npm install
npm test
```

---

### 3. 前端 (Vue + Vitest) - 12 個測試
**檔案**: `fib-fe/src/__tests__/App.spec.ts`

- ✅ 初始載入 (3 tests)
  - 抓取索引和計算值
  - 空資料顯示
  - 錯誤處理

- ✅ 表單提交 (6 tests)
  - 有效索引
  - 負數拒絕
  - 超過 40 拒絕
  - 非數字拒絕
  - 伺服器錯誤處理
  - Enter 鍵提交

- ✅ 輪詢機制 (2 tests)
  - 每 2 秒輪詢
  - 提交後輪詢

- ✅ 顯示邏輯 (1 test)
  - 多個計算值渲染

**執行**:
```bash
cd fib-fe
npm install
npm run test:unit
```

---

## 執行所有測試

```bash
# 從專案根目錄
./test-all.sh
```

或分別執行：
```bash
# 前端
cd fib-fe && npm run test:unit -- --run

# 後端
cd fib-be && pytest -v

# Worker
cd fib-worker && npm test
```

---

## CI/CD 整合

測試已準備好整合到 GitHub Actions。參考 `.github/workflows/ci.yml`（待建立）。

**關鍵點**:
- 所有測試使用 mock，無需真實 Redis/PostgreSQL
- 測試獨立，可平行執行
- 零外部依賴
