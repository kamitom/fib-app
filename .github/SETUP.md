# GitHub Actions 設定指南

## 快速開始

1. **推送到 GitHub**
   ```bash
   # 初始化 Git（如果還沒做）
   git init
   git add .
   git commit -m "Initial commit with CI/CD setup"

   # 連接遠端 repository
   git remote add origin https://github.com/YOUR_USERNAME/fib-app.git
   git branch -M main
   git push -u origin main
   ```

2. **自動觸發 CI**
   - Push 到 `main`, `master`, 或 `develop` 分支
   - 建立 Pull Request
   - GitHub Actions 會自動執行所有測試

## Workflows 說明

### 1. CI (`.github/workflows/ci.yml`)
**觸發條件**: 每次 push 或 PR

**執行內容**:
- ✅ 前端測試 (Vitest)
- ✅ 前端 type check (TypeScript)
- ✅ 前端 build
- ✅ 後端測試 (pytest)
- ✅ Worker 測試 (Jest)
- ✅ Docker images 構建

**執行時間**: ~3-5 分鐘

### 2. Test Coverage (`.github/workflows/test-coverage.yml`)
**觸發條件**: Push 到 `main`/`master` 或相關 PR

**執行內容**:
- 生成程式碼覆蓋率報告
- 上傳到 Codecov (可選)

**設定 Codecov**:
1. 前往 https://codecov.io/
2. 用 GitHub 登入
3. 啟用此 repository
4. 取得 token（如果是 private repo）
5. 在 GitHub Settings → Secrets 加入 `CODECOV_TOKEN`

### 3. Lint (`.github/workflows/lint.yml`)
**觸發條件**: 每次 push 或 PR

**執行內容**:
- 前端 TypeScript 檢查
- 後端 Python ruff linting

## Badge 設定

更新 README.md 中的 badge URL：
```markdown
![CI](https://github.com/YOUR_USERNAME/fib-app/workflows/CI/badge.svg)
```

替換 `YOUR_USERNAME` 為你的 GitHub 使用者名稱。

## 本地測試

在推送前，可以本地執行相同的測試：
```bash
# 執行所有測試（模擬 CI）
./test-all.sh

# 個別服務測試
cd fib-fe && npm run test:unit && npm run type-check && npm run build
cd fib-be && pytest -v
cd fib-worker && npm test
```

## 常見問題

### Q: CI 失敗但本地測試通過？
A: 檢查：
- Node.js / Python 版本是否一致
- 依賴是否正確安裝（`package-lock.json` / `requirements.txt`）
- 環境變數是否缺失

### Q: 如何跳過 CI？
A: Commit message 加入 `[skip ci]` 或 `[ci skip]`
```bash
git commit -m "Update docs [skip ci]"
```

### Q: 測試太慢？
A: 考慮：
- 使用 cache (已在 workflow 中設定)
- 平行執行 jobs (已設定)
- 減少不必要的依賴安裝

## 進階設定

### 加入部署 workflow

建立 `.github/workflows/deploy.yml`:
```yaml
name: Deploy to AWS

on:
  push:
    branches: [ main ]

jobs:
  deploy:
    runs-on: ubuntu-latest
    needs: [test-frontend, test-backend, test-worker]

    steps:
      - uses: actions/checkout@v4

      # AWS Elastic Beanstalk 部署
      - name: Deploy to EB
        env:
          AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
          AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
        run: |
          # EB CLI 部署命令
          eb deploy production
```

### Secrets 設定

在 GitHub Settings → Secrets 加入：
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `CODECOV_TOKEN` (如果使用 Codecov)
