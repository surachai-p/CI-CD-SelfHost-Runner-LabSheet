# ใบงาน: การ Deploy Booking App ด้วย GitHub Actions และ Self-Hosted Runner

## วัตถุประสงค์

1. เข้าใจการทำงานของ GitHub Actions Self-Hosted Runner
2. ติดตั้งและเชื่อมต่อ self-hosted runner กับ repository แบบ Private
3. ติดตั้งและรันแอป booking-app-demo-2025 บนเครื่อง local ด้วย Docker และ PostgreSQL
4. สร้าง CI/CD workflow สำหรับแอป Full-Stack
5. ทดสอบและตรวจสอบการ deploy บนเครื่อง local

## คำแนะนำเบื้องต้น

ใบงานนี้ใช้ repository `booking-app-demo-2025` ซึ่งเป็นแอป Booking System ที่มี:

- frontend: React + Vite
- backend: Node.js + Express + Prisma
- database: PostgreSQL
- CI/CD: GitHub Actions บน self-hosted runner

> หมายเหตุ: สามารถ clone repo สาธารณะ แล้วสร้าง repository ใหม่เป็น `Private` เพื่อใช้กับ self-hosted runner ได้

---

## ส่วนที่ 1: เตรียม repository

### 1.1 Clone project จาก GitHub

```bash
git clone https://github.com/surachai-p/booking-app-demo-2025.git
cd booking-app-demo-2025
```

### 1.2 สร้าง Private repository ของคุณ

1. สร้าง repository ใหม่ใน GitHub เช่น `booking-app-demo-2025-private`
2. ตั้งค่าเป็น **Private**
3. เพิ่ม remote ใหม่ และ push โค้ดขึ้น repository ของคุณ

```bash
git remote rename origin upstream
git remote add origin https://github.com/YOUR_USERNAME/booking-app-demo-2025-private.git
git push -u origin main
```

---

## ส่วนที่ 2: ติดตั้งและรันระบบบนเครื่อง local

### 2.1 Backend setup

```bash
cd backend
cp .env.example .env
```

แก้ไฟล์ `backend/.env` ให้เป็นค่าบนเครื่องคุณ เช่น:

```env
DATABASE_URL=postgresql://postgres:postgres@localhost:5432/booking_app
JWT_SECRET=your-secret-key
NODE_ENV=development
```

ติดตั้ง dependencies:

```bash
npm install
```

### 2.2 Start PostgreSQL ด้วย Docker Compose

```bash
docker compose up -d
```

ตรวจสอบ container:

```bash
docker ps | grep postgres
```

### 2.3 Prisma setup และ migrate

```bash
npx prisma generate
npx prisma migrate dev --name init
```

### 2.4 Run backend

```bash
npm run dev
```

หรือแบบ production:

```bash
npm start
```

### 2.5 Frontend setup

```bash
cd ../frontend
npm install
```

สร้างไฟล์ `frontend/.env.local`:

```env
VITE_API_URL=http://localhost:3001
```

รัน frontend:

```bash
npm run dev
```

### 2.6 ทดสอบระบบ

- Backend: `http://localhost:3001`
- Frontend: `http://localhost:5173`

ตรวจสอบ endpoint:

```bash
curl http://localhost:3001/api/bookings
```

---

## ส่วนที่ 3: อธิบายโครงสร้าง repository

โครงสร้างหลักของโปรเจค:

```
booking-app-demo-2025/
├── backend/
│   ├── server.js
│   ├── database.js
│   ├── prisma/
│   ├── docker-compose.yml
│   ├── .env.example
│   └── package.json
├── frontend/
│   ├── src/
│   ├── package.json
│   ├── vite.config.js
│   └── tailwind.config.js
├── .github/workflows/ci.yml
└── README.md
```

### จุดสำคัญ

- backend ใช้ Express, Prisma, PostgreSQL
- frontend ใช้ React, Vite, Tailwind
- database ต่างหากจาก frontend
- workflow ต้อง run บน self-hosted runner

---

## ส่วนที่ 4: ตั้งค่า Self-Hosted Runner

### 4.1 เตรียมเครื่อง

ติดตั้ง:
- Git
- Node.js 20+
- Docker (ถ้าต้องการรัน Docker Compose)

### 4.2 ลงทะเบียน runner ใน GitHub

1. ไปที่ repository ของคุณ
2. Settings > Actions > Runners
3. New self-hosted runner
4. เลือกระบบปฏิบัติการ
5. คัดลอกคำสั่ง `config` และติดตั้ง

### 4.3 ตัวอย่างบน Linux/macOS

```bash
mkdir actions-runner && cd actions-runner
curl -o actions-runner.tar.gz -L https://github.com/actions/runner/releases/download/v2.308.0/actions-runner-linux-x64-2.308.0.tar.gz
tar xzf actions-runner.tar.gz
./config.sh --url https://github.com/YOUR_USERNAME/booking-app-demo-2025-private --token YOUR_TOKEN
```

### 4.4 เริ่ม runner

```bash
./run.sh
```

ถ้าต้องการติดตั้งเป็น service:

```bash
sudo ./svc.sh install
sudo ./svc.sh start
```

### 4.5 ตรวจสอบ runner

ดูบน GitHub ว่า runner ขึ้นสถานะ **Idle**

---

## ส่วนที่ 5: workflow สำหรับ booking-app-demo-2025

### 5.1 สร้างไฟล์ `.github/workflows/ci.yml`

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

### 5.2 คำอธิบาย

- `runs-on: self-hosted` ใช้ runner ที่ติดตั้งบนเครื่องของเรา
- ติดตั้ง dependencies ของ backend และ frontend
- เปิด database ด้วย Docker Compose
- สร้าง Prisma client และรัน migrations
- build frontend ด้วย Vite

---

## ส่วนที่ 6: ทดสอบ workflow

### 6.1 Commit และ push

```bash
git add .github/workflows/ci.yml
git commit -m "Add CI workflow for self-hosted runner"
git push origin main
```

### 6.2 ตรวจสอบบน GitHub Actions

1. เข้าแท็บ **Actions**
2. เปิด workflow run ล่าสุด
3. ตรวจสอบว่า `checkout`, `install`, `docker compose`, `migrate`, `build` ผ่าน

### 6.3 ถ้า error

- runner ยังไม่รันหรือยังไม่เชื่อมต่อ
- Docker service บนเครื่องไม่ทำงาน
- `.env` ของ backend ไม่ถูกต้อง
- port 5432 ถูกใช้งานอยู่

---

## ส่วนที่ 7: ทดสอบและตรวจสอบ

### 7.1 ทดสอบ API

```bash
curl http://localhost:3001/api/bookings
```

### 7.2 ดู frontend

เปิด browser ที่ `http://localhost:5173`

### 7.3 ดู logs

```bash
docker ps
docker logs <container_id>
```

---

## ส่วนที่ 8: สรุป

- `booking-app-demo-2025` เป็นแอปจริงที่มี frontend/backend/database แยกกัน
- สามารถใช้ repository แบบ Private กับ GitHub Actions ได้
- self-hosted runner ช่วยให้เรารัน workflow บนเครื่องเองได้
- workflow ต้องจัดการทั้ง backend migrations และ frontend build

## คำถามท้ายบท

1. ทำไม self-hosted runner ถึงเหมาะสำหรับการทดสอบ deployment บนเครื่องของเรา?
2. ทำไมต้องรัน PostgreSQL ก่อน `npx prisma migrate dev`?
3. ถ้า frontend build ไม่ผ่าน ควรตรวจสอบอะไร?
4. ทำไม repository แบบ Private ยังคงใช้ GitHub Actions ได้?
