# ใบงาน Windows: การ Deploy Booking App ด้วย GitHub Actions และ Self-Hosted Runner

## วัตถุประสงค์

1. เข้าใจการติดตั้ง Self-Hosted Runner บน Windows
2. เชื่อมต่อ runner กับ repository แบบ Private
3. ติดตั้งและรัน booking-app-demo-2025 บน Windows ด้วย Docker และ PostgreSQL
4. สร้าง CI/CD workflow ที่รันบน self-hosted runner
5. ตรวจสอบและแก้ปัญหาการ deploy บน Windows

## ส่วนที่ 1: เตรียม repository

### 1.1 Clone project

```powershell
git clone https://github.com/surachai-p/booking-app-demo-2025.git
cd booking-app-demo-2025
```

### 1.2 สร้าง Private repository ของคุณ

1. สร้าง repository ใหม่บน GitHub เช่น `booking-app-demo-2025-private`
2. ตั้งค่าเป็น **Private**
3. เพิ่ม remote ใหม่และ push ขึ้น repository ของคุณ

```powershell
git remote rename origin upstream
git remote add origin https://github.com/YOUR_USERNAME/booking-app-demo-2025-private.git
git push -u origin main
```

---

## ส่วนที่ 2: ติดตั้งและรันระบบบน Windows

### 2.1 Backend setup

```powershell
cd backend
Copy-Item .env.example .env
```

แก้ `backend/.env`:

```env
DATABASE_URL=postgresql://postgres:postgres@localhost:5432/booking_app
JWT_SECRET=your-secret-key
NODE_ENV=development
```

ติดตั้ง dependencies:

```powershell
npm install
```

### 2.2 Start PostgreSQL ด้วย Docker Compose

```powershell
docker compose up -d
```

ตรวจสอบ:

```powershell
docker ps | Select-String postgres
```

### 2.3 Prisma setup และ migrate

```powershell
npx prisma generate
npx prisma migrate dev --name init
```

### 2.4 Run backend

```powershell
npm run dev
```

### 2.5 Frontend setup

```powershell
cd ../frontend
npm install
```

สร้าง `frontend/.env.local`:

```env
VITE_API_URL=http://localhost:3001
```

รัน frontend:

```powershell
npm run dev
```

---

## ส่วนที่ 3: ติดตั้ง self-hosted runner บน Windows

### 3.1 เตรียมเครื่อง

ติดตั้ง:
- Git for Windows
- Node.js 20+
- Docker Desktop
- PowerShell 7+ (แนะนำ)

### 3.2 ลงทะเบียน runner ใน GitHub

1. ไปที่ repository ของคุณ
2. Settings > Actions > Runners
3. New self-hosted runner
4. เลือกระบบปฏิบัติการเป็น Windows
5. คัดลอกคำสั่ง config

### 3.3 ตัวอย่างติดตั้งบน Windows

```powershell
mkdir actions-runner
cd actions-runner
Invoke-WebRequest -Uri https://github.com/actions/runner/releases/download/v2.308.0/actions-runner-win-x64-2.308.0.zip -OutFile actions-runner.zip
Expand-Archive actions-runner.zip
./config.cmd --url https://github.com/YOUR_USERNAME/booking-app-demo-2025-private --token YOUR_TOKEN
```

### 3.4 เริ่ม runner

```powershell
.un.cmd
```

### 3.5 ตรวจสอบสถานะ

ดูบน GitHub ว่า runner ขึ้นสถานะ Idle และพร้อมใช้งาน

---

## ส่วนที่ 4: workflow for booking-app-demo-2025

### 4.1 สร้าง `.github/workflows/ci.yml`

```yaml
name: CI

on:
  push:
    branches: [ main ]
  pull_request:

jobs:
  build:
    runs-on: self-hosted
    steps:
      - uses: actions/checkout@v4
      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: '20'

      - name: Install backend dependencies
        run: |
          cd backend
          npm install

      - name: Start PostgreSQL with Docker Compose
        run: |
          cd backend
          docker compose up -d

      - name: Generate Prisma client
        run: |
          cd backend
          npx prisma generate

      - name: Run backend migrations
        run: |
          cd backend
          npx prisma migrate dev --name init

      - name: Install frontend dependencies
        run: |
          cd frontend
          npm install

      - name: Build frontend
        run: |
          cd frontend
          npm run build
```

### 4.2 คำอธิบาย

- `runs-on: self-hosted` ใช้ runner ในเครื่องของเรา
- ติดตั้ง dependencies ทั้ง backend และ frontend
- เปิด PostgreSQL ด้วย Docker Compose
- สร้าง Prisma client และรัน migrations
- build frontend ด้วย Vite

---

## ส่วนที่ 5: ทดสอบ workflow

### 5.1 Commit และ push

```powershell
git add .github/workflows/ci.yml
git commit -m "Add CI workflow for self-hosted runner"
git push origin main
```

### 5.2 ตรวจสอบบน GitHub Actions

1. เข้าแท็บ Actions
2. เปิด run ล่าสุด
3. ตรวจสอบว่า workflow ผ่านทุก step

### 5.3 ถ้า error

- runner ยังไม่ได้รันหรือเชื่อมต่อไม่สำเร็จ
- Docker Desktop ไม่ทำงาน
- `.env` ของ backend ไม่ถูกต้อง
- port 5432 ถูกใช้งาน

---

## ส่วนที่ 6: ทดสอบแอป

### 6.1 Backend

`http://localhost:3001`

### 6.2 Frontend

`http://localhost:5173`

### 6.3 API test

```powershell
curl http://localhost:3001/api/bookings
```

### 6.4 ดู logs

```powershell
docker ps
docker logs <container_id>
```

---

## ส่วนที่ 7: สรุป

- `booking-app-demo-2025` เป็นแอป Full-Stack ที่เหมาะกับการทดลอง CI/CD จริง
- Repository แบบ Private ใช้งาน GitHub Actions ได้ปกติ
- self-hosted runner ทำให้ workflow รันบนเครื่องท้องถิ่น
- workflow ต้องจัดการ backend, database และ frontend พร้อมกัน

## คำถามท้ายบท

1. ทำไมต้องรัน Docker Compose ก่อน `prisma migrate`?
2. ถ้า Docker Desktop บน Windows ไม่ทำงาน แล้ว workflow จะล้มเหลวอย่างไร?
3. ถ้า frontend build ไม่ผ่าน ควรตรวจสอบอะไร?
4. ทำไม repository แบบ Private ยังคงใช้ GitHub Actions ได้?
