# 這是一個學習什麼是多容器化應用程式的專案

## 專案功能： 斐波那契數列（Fibonacci sequence）web app

## 這是 multi-container Application

### 系統架構
- **前端**: Vue3 Server
- **後端**: FastAPI
- **反向代理**: Nginx
- **快取層**: Redis（存儲索引和計算結果）
- **資料庫**: PostgreSQL（持久化存儲已計算過的索引）
- **背景工作**: Worker（監聽 Redis 的新索引，執行計算並回存）

### User Story
使用者透過 Fibonacci Calculator 網頁介面輸入索引數字，系統會：
1. 前端 Vue3 應用接收使用者輸入
2. FastAPI 後端處理請求
3. Redis 快取層存儲所有索引及其對應的計算值
4. Worker 後台監聽新索引，執行計算並將結果存回 Redis
5. PostgreSQL 持久化保存已計算過的索引列表

詳細的架構流程圖和 User Story 圖示請參考 [USER-STORY](USER-STORY/) 目錄

## 最終目的：完成 CI/CD 部署

### 可以部署到 GCP Cloud Run 與 AWS beanstalk
