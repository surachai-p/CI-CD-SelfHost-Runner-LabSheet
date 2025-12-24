# ใบงาน: การ Deploy แอปพลิเคชันด้วย GitHub Actions และ Self-Hosted Runner (Windows)

## 🪟 สำหรับระบบปฏิบัติการ Windows

> 📌 **หมายเหตุ:** ใบงานนี้ปรับให้เหมาะสำหรับ Windows โดยเฉพาะ ใช้ PowerShell และ Git Bash

---

## วัตถุประสงค์

1. อธิบายหลักการทำงานของ Self-Hosted Runner แบบ Pull-based Model ได้
2. ติดตั้งและกำหนดค่า Self-Hosted Runner บนเครื่อง Windows ได้
3. อธิบายกระบวนการ Polling และการสื่อสารระหว่าง Runner กับ GitHub ได้
4. สร้าง CI/CD Pipeline สำหรับ Deploy แอปพลิเคชันไปยัง on-premise server ได้
5. ตั้งค่า Reverse Proxy ด้วย Nginx สำหรับ Production Environment ได้

---

## ⚙️ ความต้องการของระบบ (Prerequisites)

### ซอฟต์แวร์ที่ต้องติดตั้ง:

1. **Git for Windows** (รวม Git Bash)
   - ดาวน์โหลด: https://git-scm.com/download/win
   - ✅ ติดตั้งพร้อม Git Bash option

2. **Node.js** (LTS version)
   - ดาวน์โหลด: https://nodejs.org/
   - แนะนำ: v18 หรือ v20

3. **Docker Desktop for Windows**
   - ดาวน์โหลด: https://www.docker.com/products/docker-desktop
   - ✅ Enable WSL 2 backend (แนะนำ)

4. **PowerShell 7+** (แนะนำ)
   - ดาวน์โหลด: https://github.com/PowerShell/PowerShell/releases
   - หรือใช้ Windows PowerShell ที่มีอยู่แล้ว

5. **Text Editor**
   - Visual Studio Code (แนะนำ): https://code.visualstudio.com/
   - หรือ Notepad++

---

## ทฤษฎีที่เกี่ยวข้อง

### 1. Self-Hosted Runner คืออะไร

Self-Hosted Runner คือเครื่อง server ที่เราติดตั้งและดูแลเอง ซึ่งทำหน้าที่รัน GitHub Actions workflows โดยใช้กลไก Pull-based (Polling) ในการรับงานจาก GitHub แทนที่จะใช้ GitHub-hosted runners (Cloud Runner ของ GitHub)

### จุดเด่นของ Pull-based Model:
- Runner เป็นฝ่าย ดึง (Pull) งานจาก GitHub ไม่ใช่ GitHub ส่ง (Push) งานมา
- Runner ทำการ Polling (ตรวจสอบเป็นระยะ) ไปที่ GitHub API
- ไม่ต้องเปิด Port ให้โลกภายนอกเข้าถึง
- ไม่ต้องมี Static IP Address

### 2. สถาปัตยกรรมการทำงาน (Architecture)

```
┌─────────────────────────────────────────────────────────────────────┐
│                        GitHub Cloud Platform                        │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌──────────────┐      ┌───────────────┐      ┌─────────────────┐   │
│  │  Repository  │      │    Actions    │      │   Job Queue     │   │
│  │   (Code)     │─────>│   Workflow    │─────>│ (Pending Jobs)  │   │
│  └──────────────┘      └───────────────┘      └─────────────────┘   │
│                                                         ▲           │
│                                                         │           │
└─────────────────────────────────────────────────────────┼─────────-─┘
                                                          │
                                                          │
                           Firewall (No Inbound Rules)    │
                           ═══════════════════════════════│═══
                                                          │
                                      HTTPS Polling       │
                                   (Outbound Connection)  │
                                                          │
                              1. "Any jobs for me?"       │
                          ┌───────────────────────────────┘
                          │
                          │  2. Response: Job Details
                          │     or "No jobs yet"
                          ▼
                  ┌─────────────────────┐
                  │   Self-Hosted       │ ← Runs on Windows PC
                  │      Runner         │   (Your Local Machine)
                  │   (Agent Process)   │
                  └─────────────────────┘
                          │
                          │ 3. Clone Repository
                          │ 4. Execute Steps
                          │ 5. Report Status
                          ▼
                  ┌─────────────────────┐
                  │  Local Deployment   │
                  │  Docker Compose     │
                  │  ├── App Container  │
                  │  └── Nginx Proxy    │
                  └─────────────────────┘
```

### 3. ขั้นตอนการทำงานโดยละเอียด

**ขั้นตอนที่ 1: Developer Push Code**

```
Developer → git push → GitHub Repository
```

- นักพัฒนา push code ขึ้น GitHub Repository (เช่น branch **main**)

**ขั้นตอนที่ 2: Workflow Triggered**

```
GitHub → Detect Push Event → Create Workflow Run → Generate Job
```

- GitHub ตรวจจับเหตุการณ์ (push, pull request, schedule)
- สร้าง Workflow Run ตามไฟล์ **.github/workflows/*.yml**
- สร้าง Job และเก็บไว้ใน Job Queue
- Job จะมี metadata: repository URL, branch, commit SHA, steps ที่ต้องทำ

**ขั้นตอนที่ 3: Runner Polling Loop**

```
Runner → HTTPS GET → GitHub API → Poll for Jobs
                                      ↓
                              Check Job Queue
                                      ↓
                         Match with Runner Labels
```

**Runner ทำงานเป็น Loop:**

```javascript
// Simplified Polling Logic
while (runner.isActive) {
  // ส่ง request ไปที่ GitHub API ทุก 1-2 วินาที
  const response = await fetch('https://api.github.com/actions/v1/jobs', {
    method: 'GET',
    headers: {
      'Authorization': `Bearer ${RUNNER_TOKEN}`,
      'Accept': 'application/json'
    },
    body: JSON.stringify({
      runnerId: 'runner-12345',
      runnerName: 'my-windows-runner',
      labels: ['self-hosted', 'Windows', 'X64'],
      timeout: 60  // Long-polling timeout
    })
  });
  
  if (response.hasJob) {
    await executeJob(response.job);
  }
  
  // ถ้าไม่มี job ก็ polling ต่อ
}
```

**Long-Polling Technique:**
- Runner เปิด HTTP connection และรอ (block) สูงสุด 60 วินาที
- ถ้ามี job ใหม่ GitHub จะ respond ทันที
- ถ้าไม่มี job ใน 60 วินาที GitHub จะ respond "no jobs" แล้ว Runner polling ใหม่
- ทำให้ได้รับ job แทบจะทันทีโดยไม่ต้องส่ง request บ่อยเกินไป

---

## การปฏิบัติการทดลอง

### ส่วนที่ 1: เตรียมโครงสร้างโปรเจค

#### 1.1 สร้าง Repository บน GitHub

1. ไปที่ https://github.com
2. คลิก **New repository**
3. ตั้งชื่อ: `nodejs-cicd-selfhosted`
4. เลือก: **Private** (สำคัญมาก!)
5. เลือก: Add a README file
6. คลิก **Create repository**

> ⚠️ **สำคัญ:** ต้องเป็น Private Repository เท่านั้น เพราะ Self-Hosted Runner จะรันโค้ดบนเครื่องของเรา

#### 1.2 Clone Repository มาที่เครื่อง Local

เปิด **Git Bash** และรันคำสั่ง:

```bash
# Clone repository
git clone https://github.com/YOUR_USERNAME/nodejs-cicd-selfhosted.git

# เข้าไปในโฟลเดอร์
cd nodejs-cicd-selfhosted
```

#### 1.3 สร้างโครงสร้างโปรเจค

**ใช้ Git Bash เพื่อรันคำสั่งสร้างไฟล์ หรือใช้ VS Code สร้างทีละไฟล์** 

```bash
# สร้างโฟลเดอร์และไฟล์
mkdir -p .github/workflows

# สร้างไฟล์พื้นฐาน
touch server.js
touch package.json
touch Dockerfile
touch docker-compose.yml
touch nginx.conf
touch .gitignore
touch .dockerignore
```



---

### ส่วนที่ 2: สร้าง Node.js Application

#### 2.1 สร้างไฟล์ package.json

**เปิดไฟล์ `package.json` ด้วย VS Code หรือ Notepad++ แล้ววางโค้ดนี้:**

```json
{
  "name": "nodejs-cicd-selfhosted",
  "version": "1.0.0",
  "description": "CI/CD Demo with Self-Hosted GitHub Actions Runner on Windows",
  "main": "server.js",
  "scripts": {
    "start": "node server.js",
    "dev": "nodemon server.js"
  },
  "keywords": [
    "nodejs",
    "cicd",
    "docker",
    "self-hosted",
    "github-actions",
    "windows"
  ],
  "author": "",
  "license": "MIT",
  "dependencies": {
    "express": "^4.21.0"
  },
  "devDependencies": {
    "nodemon": "^3.0.2"
  }
}
```

#### 2.2 สร้าง package-lock.json (สำคัญมาก!)

> 🔑 **Critical:** ไฟล์นี้จำเป็นสำหรับการใช้ `npm ci` ใน production

**ใช้ Git Bash หรือ PowerShell:**

```bash
# ติดตั้ง dependencies และสร้าง package-lock.json
npm install

# ตรวจสอบว่ามีไฟล์แล้ว
```

**ตรวจสอบใน PowerShell:**
```powershell
Get-ChildItem | Where-Object { $_.Name -like "*package-lock.json*" }
```

**ตรวจสอบใน Git Bash:**
```bash
ls -la | grep package-lock.json
```

**ผลลัพธ์ที่ควรเห็น:**
```
-rw-r--r--  1 user  staff  123456 Dec 23 10:00 package-lock.json
```

#### 2.3 สร้าง server.js

**เปิดไฟล์ `server.js` แล้ววางโค้ดนี้:**

```js
const express = require('express');
const app = express();
const PORT = process.env.PORT || 3000;

// Middleware
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// Routes
app.get('/', (req, res) => {
  res.json({
    message: '🚀 Hello from Self-Hosted CI/CD on Windows!',
    version: process.env.VERSION || '1.0.0',
    environment: process.env.NODE_ENV || 'development',
    platform: process.platform,
    timestamp: new Date().toISOString(),
    deployment: 'Pull-based Runner Architecture (Windows)'
  });
});

app.get('/health', (req, res) => {
  res.status(200).json({
    status: 'healthy',
    uptime: Math.floor(process.uptime()),
    timestamp: new Date().toISOString(),
    platform: process.platform
  });
});

app.get('/api/info', (req, res) => {
  res.json({
    app: 'Node.js CI/CD Demo (Windows)',
    version: process.env.VERSION || '1.0.0',
    node: process.version,
    platform: process.platform,
    arch: process.arch,
    memory: {
      total: Math.round(process.memoryUsage().heapTotal / 1024 / 1024) + ' MB',
      used: Math.round(process.memoryUsage().heapUsed / 1024 / 1024) + ' MB'
    }
  });
});

// 404 handler
app.use((req, res) => {
  res.status(404).json({
    error: 'Not Found',
    path: req.path
  });
});

// Error handler
app.use((err, req, res, next) => {
  console.error(err.stack);
  res.status(500).json({
    error: 'Internal Server Error',
    message: err.message
  });
});

// Start server
app.listen(PORT, () => {
  console.log(`🚀 Server is running on port ${PORT}`);
  console.log(`📦 Version: ${process.env.VERSION || '1.0.0'}`);
  console.log(`🌍 Environment: ${process.env.NODE_ENV || 'development'}`);
  console.log(`💻 Platform: ${process.platform}`);
  console.log(`🔗 Health check: http://localhost:${PORT}/health`);
});
```

---

### ส่วนที่ 3: สร้าง Docker Configuration

#### 3.1 สร้าง Dockerfile (Production-Ready)

**เปิดไฟล์ `Dockerfile` แล้ววางโค้ดนี้:**

```dockerfile
# ═══════════════════════════════════════════════════════════
# Stage 1: Production Dependencies
# ═══════════════════════════════════════════════════════════
FROM node:18-alpine AS prod-dependencies

WORKDIR /app

# Copy package files
COPY package*.json ./

# ⚠️ Critical: ใช้ npm ci สำหรับ production builds
# npm ci ต้องการ package-lock.json และเร็วกว่า npm install
RUN npm ci --omit=dev && \
    npm cache clean --force

# ═══════════════════════════════════════════════════════════
# Stage 2: Production Build
# ═══════════════════════════════════════════════════════════
FROM node:18-alpine AS production

# Add metadata
LABEL maintainer="your-email@example.com"
LABEL description="Production Node.js Application on Windows"
LABEL version="1.0.0"

# Install dumb-init for proper signal handling
RUN apk add --no-cache dumb-init

WORKDIR /app

# Copy production dependencies
COPY --from=prod-dependencies /app/node_modules ./node_modules

# Copy application code
COPY --chown=node:node . .

# Use built-in 'node' user (non-root)
USER node

# Expose port
EXPOSE 3000

# Environment
ENV NODE_ENV=production \
    PORT=3000

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD node -e "require('http').get('http://localhost:3000/health', (r) => {process.exit(r.statusCode === 200 ? 0 : 1)})"

# Use dumb-init to handle signals properly
ENTRYPOINT ["dumb-init", "--"]

# Start application
CMD ["node", "server.js"]
```

**อธิบายสำคัญ:**
- ✅ ใช้ Multi-stage build เพื่อลดขนาด image
- ✅ ใช้ `npm ci --omit=dev` แทน `npm install --production`
- ✅ ต้องมี `package-lock.json` ใน repository
- ✅ ใช้ non-root user เพื่อความปลอดภัย
- ✅ มี health check

#### 3.2 สร้าง .dockerignore

**เปิดไฟล์ `.dockerignore` แล้ววางโค้ดนี้:**

```
# Dependencies
node_modules
npm-debug.log*

# ⚠️ KEEP package-lock.json - required for npm ci
# DO NOT add package-lock.json here

# Git
.git
.gitignore

# Docker
.dockerignore
Dockerfile
docker-compose*.yml

# CI/CD
.github/

# Documentation
*.md
README.md

# OS
.DS_Store
Thumbs.db
desktop.ini

# IDE
.vscode/
.idea/
*.swp

# Windows specific
$RECYCLE.BIN/
*.lnk
```

#### 3.3 สร้าง docker-compose.yml

**เปิดไฟล์ `docker-compose.yml` แล้ววางโค้ดนี้:**

```yaml
services:
  # ═══════════════════════════════════════════════════════════
  # Application Service
  # ═══════════════════════════════════════════════════════════
  app:
    build:
      context: .
      dockerfile: Dockerfile
      target: production
    image: nodejs-selfhosted-app:${VERSION:-latest}
    container_name: nodejs-selfhosted-app
    restart: unless-stopped
    environment:
      - NODE_ENV=production
      - VERSION=${VERSION:-1.0.0}
      - PORT=3000
    networks:
      - selfhosted-network
    healthcheck:
      test: ["CMD", "node", "-e", "require('http').get('http://localhost:3000/health', (r) => {process.exit(r.statusCode === 200 ? 0 : 1)})"]
      interval: 30s
      timeout: 3s
      retries: 3
      start_period: 10s
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  # ═══════════════════════════════════════════════════════════
  # Nginx Reverse Proxy
  # ═══════════════════════════════════════════════════════════
  nginx:
    image: nginx:alpine
    container_name: nginx-selfhosted-proxy
    restart: unless-stopped
    ports:
      - "8080:80"
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf:ro
    depends_on:
      app:
        condition: service_healthy
    networks:
      - selfhosted-network
    healthcheck:
      test: ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost:80/health"]
      interval: 30s
      timeout: 3s
      retries: 3
      start_period: 5s
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

networks:
  selfhosted-network:
    driver: bridge
    name: selfhosted-network
```

#### 3.4 สร้าง nginx.conf

**เปิดไฟล์ `nginx.conf` แล้ววางโค้ดนี้:**

```nginx
events {
    worker_connections 1024;
}

http {
    # Basic Settings
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;

    # Logging
    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log;

    # Gzip Compression
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types text/plain text/css text/xml text/javascript 
               application/json application/javascript application/xml+rss;

    # Upstream backend
    upstream nodejs_backend {
        server app:3000 max_fails=3 fail_timeout=30s;
    }

    server {
        listen 80;
        server_name _;

        # Security Headers
        add_header X-Frame-Options "SAMEORIGIN" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header X-XSS-Protection "1; mode=block" always;

        # Root location
        location / {
            proxy_pass http://nodejs_backend;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection 'upgrade';
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_cache_bypass $http_upgrade;
            
            # Timeouts
            proxy_connect_timeout 60s;
            proxy_send_timeout 60s;
            proxy_read_timeout 60s;
        }

        # Health check endpoint
        location /health {
            proxy_pass http://nodejs_backend/health;
            access_log off;
        }
    }
}
```

#### 3.5 สร้าง .gitignore

**เปิดไฟล์ `.gitignore` แล้ววางโค้ดนี้:**

```
# Dependencies
node_modules/

# ⚠️ DO NOT ignore package-lock.json
# package-lock.json is REQUIRED for production builds

# Logs
*.log
npm-debug.log*

# Environment
.env
.env.local
.env.production

# OS - Windows specific
.DS_Store
Thumbs.db
desktop.ini
$RECYCLE.BIN/
*.lnk

# IDE
.vscode/
.idea/
*.swp

# Docker
.docker/
```

#### 3.6 ทดสอบ Build Local

**ใช้ PowerShell หรือ Git Bash:**

```bash
# ทดสอบ build Docker image
docker build -t nodejs-selfhosted-app:test .

# ถ้า build สำเร็จ ให้ทดสอบรัน
docker run --rm -p 3001:3000 nodejs-selfhosted-app:test

# ทดสอบในหน้าต่าง PowerShell/Git Bash อื่น
curl http://localhost:3001
curl http://localhost:3001/health

# กด Ctrl+C เพื่อหยุด
```

**ใช้ PowerShell (ถ้า curl ไม่มี):**
```powershell
Invoke-WebRequest http://localhost:3001 | Select-Object -ExpandProperty Content
Invoke-WebRequest http://localhost:3001/health | Select-Object -ExpandProperty Content
```

**ผลลัพธ์ที่ควรเห็น:**
```json
{
  "message": "🚀 Hello from Self-Hosted CI/CD on Windows!",
  "version": "1.0.0",
  "environment": "production",
  "platform": "linux",
  "timestamp": "2024-12-23T10:30:00.000Z",
  "deployment": "Pull-based Runner Architecture (Windows)"
}
```

---

### ส่วนที่ 4: สร้าง GitHub Actions Workflow

#### 4.1 สร้าง Workflow File

**สร้างโฟลเดอร์และไฟล์:**

**PowerShell:**
```powershell
New-Item -ItemType Directory -Path .github\workflows -Force
New-Item -ItemType File -Path .github\workflows\deploy.yml -Force
```

**Git Bash:**
```bash
mkdir -p .github/workflows
touch .github/workflows/deploy.yml
```

#### 4.2 เปิดไฟล์ `.github/workflows/deploy.yml` แล้ววางโค้ดนี้:

```yaml
name: 🚀 Deploy to Self-Hosted Server (Windows)

on:
  push:
    branches: 
      - main
  workflow_dispatch:

env:
  VERSION: "1.0.${{ github.run_number }}"

jobs:
  deploy:
    name: 🚀 Deploy Application
    runs-on: self-hosted
    
    steps:
      # ================================================================
      # Step 1: Checkout Code
      # ================================================================
      - name: 📥 Checkout Code
        uses: actions/checkout@v4

      # ================================================================
      # Step 2: Set Version
      # ================================================================
      - name: 🏷️ Set Version
        shell: bash
        run: |
          echo "VERSION=1.0.${{ github.run_number }}" >> $GITHUB_ENV
          echo "📦 Deploying Version: 1.0.${{ github.run_number }}"

      # ================================================================
      # Step 3: Display Environment Info
      # ================================================================
      - name: 📊 Display Environment
        shell: bash
        run: |
          echo "════════════════════════════════════════"
          echo "🚀 Deployment Information"
          echo "════════════════════════════════════════"
          echo "📦 Version: 1.0.${{ github.run_number }}"
          echo "🌿 Branch: ${{ github.ref_name }}"
          echo "👤 Author: ${{ github.actor }}"
          echo "💬 Commit: ${{ github.event.head_commit.message }}"
          echo "🔗 Commit SHA: ${{ github.sha }}"
          echo "════════════════════════════════════════"
          echo ""
          echo "📋 System Information:"
          echo "OS: Windows (Self-Hosted Runner)"
          echo "Node: $(node --version)"
          echo "NPM: $(npm --version)"
          echo "Docker: $(docker --version)"
          echo "════════════════════════════════════════"

      # ================================================================
      # Step 4: Verify Dependencies (Critical!)
      # ================================================================
      - name: 🔍 Verify package-lock.json
        shell: bash
        run: |
          echo "🔍 Checking package-lock.json..."
          
          if [ ! -f "package-lock.json" ]; then
            echo "❌ package-lock.json not found!"
            echo "⚠️  This file is required for production builds with npm ci"
            exit 1
          fi
          
          echo "✅ package-lock.json found"
          
          # Check lockfile version
          LOCKFILE_VERSION=$(cat package-lock.json | grep '"lockfileVersion"' | head -1 | grep -o '[0-9]')
          echo "📋 Lockfile version: $LOCKFILE_VERSION"

      # ================================================================
      # Step 5: Stop Existing Services
      # ================================================================
      - name: 🛑 Stop Existing Services
        shell: bash
        run: |
          echo "🛑 Stopping existing services..."
          docker-compose down --remove-orphans || echo "No services to stop"
          
          # Clean up old images (keep last 3 versions)
          echo "🧹 Cleaning old images..."
          docker images nodejs-selfhosted-app --format "{{.ID}} {{.Tag}}" | \
            grep -v latest | \
            tail -n +4 | \
            awk '{print $1}' | \
            xargs -r docker rmi -f || echo "No old images to remove"

      # ================================================================
      # Step 6: Build Docker Image
      # ================================================================
      - name: 🔨 Build Docker Image
        shell: bash
        run: |
          echo "🔨 Building Docker image with npm ci..."
          
          docker build \
            --build-arg VERSION=${{ env.VERSION }} \
            --tag nodejs-selfhosted-app:${{ env.VERSION }} \
            --tag nodejs-selfhosted-app:latest \
            --target production \
            .
          
          if [ $? -eq 0 ]; then
            echo "✅ Docker image built successfully"
            docker images | grep nodejs-selfhosted-app
          else
            echo "❌ Docker build failed"
            exit 1
          fi

      # ================================================================
      # Step 7: Start Services
      # ================================================================
      - name: 🚀 Start Services
        shell: bash
        run: |
          echo "🚀 Starting services..."
          VERSION=${{ env.VERSION }} docker-compose up -d
          
          echo "⏳ Waiting for services to be ready..."
          sleep 15

      # ================================================================
      # Step 8: Check Service Health
      # ================================================================
      - name: 🏥 Check Service Health
        shell: bash
        run: |
          echo "🏥 Checking service health..."
          
          # Check app container
          if docker ps | grep -q nodejs-selfhosted-app; then
            echo "✅ App container is running"
          else
            echo "❌ App container is not running"
            docker ps -a | grep nodejs-selfhosted-app
            exit 1
          fi
          
          # Check nginx container
          if docker ps | grep -q nginx-selfhosted-proxy; then
            echo "✅ Nginx container is running"
          else
            echo "❌ Nginx container is not running"
            docker ps -a | grep nginx-selfhosted-proxy
            exit 1
          fi
          
          # Wait for health checks
          echo "⏳ Waiting for health checks..."
          sleep 5
          
          # Test health endpoint
          echo "🧪 Testing health endpoint..."
          for i in {1..15}; do
            HEALTH_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/health)
            
            if [ "$HEALTH_STATUS" = "200" ]; then
              echo "✅ Health check passed (Status: $HEALTH_STATUS)"
              break
            fi
            
            if [ $i -eq 15 ]; then
              echo "❌ Health check failed after 15 attempts (Status: $HEALTH_STATUS)"
              docker-compose logs
              exit 1
            fi
            
            echo "⏳ Attempt $i/15 - Waiting... (Status: $HEALTH_STATUS)"
            sleep 2
          done

      # ================================================================
      # Step 9: Test Application
      # ================================================================
      - name: 🧪 Test Application
        shell: bash
        run: |
          echo "🧪 Testing application endpoints..."
          
          # Test root endpoint
          echo "Testing GET /"
          RESPONSE=$(curl -s http://localhost:8080/)
          echo "$RESPONSE" | jq '.'
          
          if echo "$RESPONSE" | jq -e '.version' > /dev/null; then
            echo "✅ Root endpoint is working"
          else
            echo "❌ Root endpoint failed"
            exit 1
          fi
          
          # Test info endpoint
          echo ""
          echo "Testing GET /api/info"
          curl -s http://localhost:8080/api/info | jq '.'

      # ================================================================
      # Step 10: Display Status
      # ================================================================
      - name: 📊 Display Status
        shell: bash
        run: |
          echo "════════════════════════════════════════"
          echo "📊 Deployment Status"
          echo "════════════════════════════════════════"
          echo ""
          echo "🐳 Running Containers:"
          docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
          echo ""
          echo "📦 Images:"
          docker images | grep nodejs-selfhosted-app | head -5
          echo "════════════════════════════════════════"

      # ================================================================
      # Step 11: Display Logs
      # ================================================================
      - name: 📝 Display Logs
        if: always()
        shell: bash
        run: |
          echo "════════════════════════════════════════"
          echo "📝 Application Logs"
          echo "════════════════════════════════════════"
          docker logs nodejs-selfhosted-app --tail 50 || echo "No app logs"
          echo ""
          echo "════════════════════════════════════════"
          echo "📝 Nginx Logs"
          echo "════════════════════════════════════════"
          docker logs nginx-selfhosted-proxy --tail 50 || echo "No nginx logs"

      # ================================================================
      # Step 12: Deployment Summary
      # ================================================================
      - name: 🎉 Deployment Summary
        if: success()
        shell: bash
        run: |
          echo "════════════════════════════════════════"
          echo "✅ Deployment Successful!"
          echo "════════════════════════════════════════"
          echo "📦 Version: ${{ env.VERSION }}"
          echo "🔗 Application: http://localhost:8080"
          echo "🏥 Health Check: http://localhost:8080/health"
          echo "📊 Info: http://localhost:8080/api/info"
          echo "📅 Deployed: $(date)"
          echo "👤 By: ${{ github.actor }}"
          echo "💻 Platform: Windows (Self-Hosted)"
          echo "════════════════════════════════════════"
```

**หมายเหตุสำคัญ:**
- ✅ ใช้ `shell: bash` ในทุก step (จะใช้ Git Bash บน Windows)
- ✅ Workflow จะรันบน Self-Hosted Runner ที่ติดตั้งบน Windows

---

### ส่วนที่ 5: Commit และ Push Code

**ใช้ Git Bash หรือ PowerShell:**

```bash
# เพิ่มไฟล์ทั้งหมด
git add .

# ตรวจสอบว่ามี package-lock.json
git status
```

**ควรเห็น:**
```
new file:   package-lock.json
new file:   server.js
new file:   package.json
new file:   Dockerfile
new file:   docker-compose.yml
...
```

```bash
# Commit
git commit -m "Initial commit: Node.js app with CI/CD on Windows Self-Hosted Runner"

# Push
git push origin main
```

> ⚠️ **ตรวจสอบ:** ต้องแน่ใจว่า `package-lock.json` ถูก commit ด้วย!

---

### ส่วนที่ 6: ติดตั้ง Self-Hosted Runner บน Windows

#### 6.1 ไปที่ Repository Settings

1. ไปที่ GitHub repository
2. คลิก **Settings**
3. ไปที่ **Actions** → **Runners**
4. คลิก **New self-hosted runner**

#### 6.2 เลือก Operating System

เลือก **Windows** → เลือก Architecture **x64**

#### 6.3 Download และติดตั้ง Runner

**เปิด PowerShell (Run as Administrator)**

```powershell
# สร้างโฟลเดอร์
New-Item -ItemType Directory -Path C:\actions-runner -Force
Set-Location C:\actions-runner

# Download Runner (ใช้ URL จาก GitHub Settings)
# เปลี่ยน version ตามที่ GitHub แสดง
Invoke-WebRequest -Uri "https://github.com/actions/runner/releases/download/v2.311.0/actions-runner-win-x64-2.311.0.zip" -OutFile "actions-runner-win-x64-2.311.0.zip"

# Extract
Expand-Archive -Path .\actions-runner-win-x64-2.311.0.zip -DestinationPath . -Force

# Configure Runner
# คัดลอกคำสั่งจาก GitHub Settings → Actions → Runners
.\config.cmd --url https://github.com/YOUR_USERNAME/nodejs-cicd-selfhosted --token YOUR_TOKEN
```

**ตอบคำถาม:**
```
Enter the name of the runner group: [press Enter for default]
Enter the name of runner: my-windows-runner
Enter any additional labels: [press Enter]
Enter name of work folder: [press Enter for _work]
```

**ผลลัพธ์ที่ควรเห็น:**
```
√ Runner successfully added
√ Runner connection is good

# Settings Saved.
```

#### 6.4 เริ่มต้น Runner

**แบบ Interactive (สำหรับทดสอบ):**

```powershell
# รันคำสั่ง
.\run.cmd
```

**ผลลัพธ์ที่ควรเห็น:**
```
√ Connected to GitHub

Current runner version: '2.311.0'
2024-12-23 10:00:00Z: Listening for Jobs
```

**แบบ Service (รันอัตโนมัติ):** ⭐ **แนะนำสำหรับ Production**

**ต้อง Run PowerShell as Administrator:**

```powershell
# Install service
.\svc.cmd install

# Start service
.\svc.cmd start

# Check status
.\svc.cmd status
```

**ผลลัพธ์:**
```
Service actions.runner.YOUR_USERNAME-nodejs-cicd-selfhosted.my-windows-runner started successfully
```

**ดู Logs:**
```powershell
# View logs
Get-Content -Path "_diag\Runner_*.log" -Wait -Tail 50
```

**Uninstall Service (ถ้าต้องการ):**
```powershell
.\svc.cmd stop
.\svc.cmd uninstall
```

#### 6.5 ตรวจสอบ Runner บน GitHub

1. กลับไปที่ **Settings** → **Actions** → **Runners**
2. ควรเห็น runner แสดงสถานะ **Idle** สีเขียว
3. Label ควรมี: `self-hosted`, `Windows`, `X64`

### บันทึกรูปผลการทดลอง

```
บันทึกรูปหน้า Runners โดยคัดลอกให้เห็น Account ของ GitHub และ Repository
และแสดง Runner status เป็น "Idle" สีเขียว
```
<img width="1919" height="1036" alt="image" src="https://github.com/user-attachments/assets/c182e5f6-b6de-47ad-98fc-3723a3fde8ca" />

---

### ส่วนที่ 7: ทดสอบ CI/CD Pipeline

#### 7.1 แก้ไข server.js และ Push

**เปิดไฟล์ `server.js` และแก้ไข message:**

```js
app.get('/', (req, res) => {
  res.json({
    message: '🎉 Updated! Pull-based Runner on Windows Works!',
    version: process.env.VERSION || '1.0.0',
    environment: process.env.NODE_ENV || 'development',
    platform: process.platform,
    timestamp: new Date().toISOString(),
    architecture: 'Pull-based (Polling) on Windows',
    security: 'No inbound ports required'
  });
});
```

**Commit และ Push (Git Bash หรือ PowerShell):**

```bash
git add server.js
git commit -m "Update: Test CI/CD pipeline with Windows self-hosted runner"
git push origin main
```

#### 7.2 ติดตาม Deployment

**1. ดู Runner Logs (PowerShell):**

```powershell
# ถ้ารันแบบ Interactive
# ดูใน terminal ที่รัน .\run.cmd

# ถ้ารันแบบ Service
Get-Content -Path "C:\actions-runner\_diag\Runner_*.log" -Wait -Tail 100
```

**ผลลัพธ์:**
```
[2024-12-23 10:30:00] Polling for jobs...
[2024-12-23 10:30:15] Job assigned: deploy
[2024-12-23 10:30:16] Running: Checkout Code
[2024-12-23 10:30:20] Running: Build Docker Image
[2024-12-23 10:32:30] Running: Start Services
[2024-12-23 10:32:45] Job completed: success
[2024-12-23 10:32:46] Polling for jobs...
```

**2. ดูบน GitHub:**
- ไปที่ **Actions** tab
- คลิกที่ workflow run ล่าสุด
- ดู logs real-time

**3. ทดสอบ Application (Git Bash หรือ PowerShell):**

**Git Bash:**
```bash
# ทดสอบ endpoint
curl http://localhost:8080

# ดู containers
docker ps

# ดู logs
docker logs nodejs-selfhosted-app
```

**PowerShell:**
```powershell
# ทดสอบ endpoint
Invoke-WebRequest http://localhost:8080 | Select-Object -ExpandProperty Content

# ดู containers
docker ps

# ดู logs
docker logs nodejs-selfhosted-app
```

### บันทึกผลการรันคำสั่ง docker logs nodejs-selfhosted-app

```txt
บันทึกรูปผลการรันคำสั่ง
```
- ผม Deploy ไม่ได้เลยครับ แก้หลายรอบมากเลยครับ Deploy ก็เกิดการ Failed ทุกรอบเลยครับ
---

### ส่วนที่ 8: Monitoring และ Troubleshooting

#### 8.1 สร้าง Monitoring Script (monitor.ps1)

**สร้างไฟล์ `monitor.ps1` ใน root project:**

```powershell
# monitor.ps1
# CI/CD Deployment Monitor for Windows

Write-Host "════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "🔍 CI/CD Deployment Monitor (Windows)" -ForegroundColor White
Write-Host "════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

# ═══════════════════════════════════════════════════════════
# Check Runner Status
# ═══════════════════════════════════════════════════════════
Write-Host "📊 Runner Status:" -ForegroundColor Yellow

try {
    $runnerProcess = Get-Process | Where-Object { 
        $_.ProcessName -like "*Runner.Listener*" -or 
        $_.ProcessName -like "*Runner.Worker*" 
    }
    
    if ($runnerProcess) {
        Write-Host "  ✅ Runner: " -NoNewline -ForegroundColor Green
        Write-Host "Running" -ForegroundColor White
        
        # แสดงรายละเอียด process
        foreach ($proc in $runnerProcess) {
            $cpuUsage = [math]::Round($proc.CPU, 2)
            $memoryMB = [math]::Round($proc.WorkingSet / 1MB, 2)
            Write-Host "     PID: $($proc.Id), CPU: $cpuUsage s, Memory: $memoryMB MB" -ForegroundColor Gray
        }
    } else {
        Write-Host "  ❌ Runner: " -NoNewline -ForegroundColor Red
        Write-Host "Not Running" -ForegroundColor White
        Write-Host "     Hint: Run '.\run.cmd' in C:\actions-runner" -ForegroundColor Gray
    }
} catch {
    Write-Host "  ⚠️  Error checking Runner: $($_.Exception.Message)" -ForegroundColor Yellow
}

Write-Host ""

# ═══════════════════════════════════════════════════════════
# Check Docker Containers
# ═══════════════════════════════════════════════════════════
Write-Host "🐳 Container Status:" -ForegroundColor Yellow

# Check App Container
try {
    $appContainer = docker ps --filter "name=nodejs-selfhosted-app" --format "{{.Names}}" 2>$null
    
    if ($appContainer) {
        Write-Host "  ✅ App: " -NoNewline -ForegroundColor Green
        Write-Host "Running" -ForegroundColor White
        
        $appStatus = docker ps --filter "name=nodejs-selfhosted-app" --format "{{.Status}}" 2>$null
        Write-Host "     Uptime: $appStatus" -ForegroundColor Gray
        
        # Check health
        $appHealth = docker inspect nodejs-selfhosted-app --format "{{.State.Health.Status}}" 2>$null
        if ($appHealth) {
            $healthColor = if ($appHealth -eq "healthy") { "Green" } else { "Yellow" }
            Write-Host "     Health: $appHealth" -ForegroundColor $healthColor
        }
    } else {
        Write-Host "  ❌ App: " -NoNewline -ForegroundColor Red
        Write-Host "Not Running" -ForegroundColor White
        Write-Host "     Hint: Run 'docker-compose up -d'" -ForegroundColor Gray
    }
} catch {
    Write-Host "  ⚠️  Error checking App container: $($_.Exception.Message)" -ForegroundColor Yellow
}

# Check Nginx Container
try {
    $nginxContainer = docker ps --filter "name=nginx-selfhosted-proxy" --format "{{.Names}}" 2>$null
    
    if ($nginxContainer) {
        Write-Host "  ✅ Nginx: " -NoNewline -ForegroundColor Green
        Write-Host "Running" -ForegroundColor White
        
        $nginxStatus = docker ps --filter "name=nginx-selfhosted-proxy" --format "{{.Status}}" 2>$null
        Write-Host "     Uptime: $nginxStatus" -ForegroundColor Gray
    } else {
        Write-Host "  ❌ Nginx: " -NoNewline -ForegroundColor Red
        Write-Host "Not Running" -ForegroundColor White
    }
} catch {
    Write-Host "  ⚠️  Error checking Nginx container: $($_.Exception.Message)" -ForegroundColor Yellow
}

Write-Host ""

# ═══════════════════════════════════════════════════════════
# Check Endpoints
# ═══════════════════════════════════════════════════════════
Write-Host "🌐 Endpoint Status:" -ForegroundColor Yellow

# Health Endpoint
try {
    $healthResponse = Invoke-WebRequest -Uri "http://localhost:8080/health" -UseBasicParsing -TimeoutSec 3 -ErrorAction Stop
    
    if ($healthResponse.StatusCode -eq 200) {
        Write-Host "  ✅ Health: " -NoNewline -ForegroundColor Green
        Write-Host "$($healthResponse.StatusCode)" -ForegroundColor White
        
        # Parse JSON response
        $healthContent = $healthResponse.Content | ConvertFrom-Json
        if ($healthContent.status) {
            Write-Host "     Status: $($healthContent.status)" -ForegroundColor Gray
        }
        if ($healthContent.uptime) {
            Write-Host "     Uptime: $($healthContent.uptime) seconds" -ForegroundColor Gray
        }
    } else {
        Write-Host "  ⚠️  Health: " -NoNewline -ForegroundColor Yellow
        Write-Host "$($healthResponse.StatusCode)" -ForegroundColor White
    }
} catch {
    Write-Host "  ❌ Health: " -NoNewline -ForegroundColor Red
    Write-Host "Connection Failed" -ForegroundColor White
}

# Root Endpoint
try {
    $rootResponse = Invoke-WebRequest -Uri "http://localhost:8080/" -UseBasicParsing -TimeoutSec 3 -ErrorAction Stop
    
    if ($rootResponse.StatusCode -eq 200) {
        Write-Host "  ✅ Root: " -NoNewline -ForegroundColor Green
        Write-Host "$($rootResponse.StatusCode)" -ForegroundColor White
        
        # Parse JSON response
        $rootContent = $rootResponse.Content | ConvertFrom-Json
        if ($rootContent.version) {
            Write-Host "     Version: $($rootContent.version)" -ForegroundColor Gray
        }
        if ($rootContent.message) {
            Write-Host "     Message: $($rootContent.message)" -ForegroundColor Gray
        }
    } else {
        Write-Host "  ⚠️  Root: " -NoNewline -ForegroundColor Yellow
        Write-Host "$($rootResponse.StatusCode)" -ForegroundColor White
    }
} catch {
    Write-Host "  ❌ Root: " -NoNewline -ForegroundColor Red
    Write-Host "Connection Failed" -ForegroundColor White
}

Write-Host ""

# ═══════════════════════════════════════════════════════════
# Resource Usage
# ═══════════════════════════════════════════════════════════
Write-Host "💾 Resource Usage:" -ForegroundColor Yellow

try {
    $dockerStats = docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}" 2>$null
    
    if ($dockerStats) {
        $dockerStats | ForEach-Object {
            Write-Host "  $_" -ForegroundColor White
        }
    } else {
        Write-Host "  No containers running" -ForegroundColor Gray
    }
} catch {
    Write-Host "  ⚠️  Error getting Docker stats: $($_.Exception.Message)" -ForegroundColor Yellow
}

Write-Host ""

# ═══════════════════════════════════════════════════════════
# System Information
# ═══════════════════════════════════════════════════════════
Write-Host "💻 System Information:" -ForegroundColor Yellow

# Docker Version
try {
    $dockerVersion = docker version --format "{{.Server.Version}}" 2>$null
    Write-Host "  Docker: v$dockerVersion" -ForegroundColor White
} catch {
    Write-Host "  Docker: Not installed or not running" -ForegroundColor Red
}

# Node.js Version
try {
    $nodeVersion = node --version 2>$null
    Write-Host "  Node.js: $nodeVersion" -ForegroundColor White
} catch {
    Write-Host "  Node.js: Not installed" -ForegroundColor Red
}

# NPM Version
try {
    $npmVersion = npm --version 2>$null
    Write-Host "  NPM: v$npmVersion" -ForegroundColor White
} catch {
    Write-Host "  NPM: Not installed" -ForegroundColor Red
}

# Windows Version
$windowsVersion = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").ProductName
Write-Host "  OS: $windowsVersion" -ForegroundColor White

Write-Host ""
Write-Host "════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "Last updated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
Write-Host "════════════════════════════════════════" -ForegroundColor Cyan
```

#### 8.2 ใช้ Monitoring Script

**PowerShell:**

```powershell
# Run once
.\monitor.ps1

# Run continuously (every 10 seconds)
while ($true) {
  Clear-Host
  .\monitor.ps1
  Start-Sleep -Seconds 10
}
```

**หมายเหตุ:** ถ้า PowerShell บอกว่า execution policy ไม่อนุญาต:

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### บันทึกผลการรัน monitor.ps1

```txt
บันทึกรูปผลการรันคำสั่ง
```

---

## 🎯 สรุปจุดสำคัญ

### ✅ ข้อสำคัญสำหรับ Production บน Windows

1. **ต้องมี package-lock.json**
   - ใช้ `npm ci` แทน `npm install`
   - Build เร็วกว่าและเหมือนกันทุกครั้ง
   - ต้อง commit ลง git

2. **ใช้ Multi-stage Docker Build**
   - ลดขนาด image
   - แยก dev และ production dependencies
   - ปลอดภัยกว่า

3. **Non-root User**
   - ใช้ user `node` ใน container
   - เพิ่มความปลอดภัย

4. **Health Checks**
   - ทั้ง Docker และ Compose level
   - ตรวจสอบก่อน deploy

5. **Pull-based Architecture**
   - Runner เป็นฝ่าย poll
   - ไม่ต้องเปิด port
   - ปลอดภัยกว่า push-based
   - ทำงานได้ดีบน Windows

6. **ใช้ Git Bash**
   - รัน workflow steps ด้วย `shell: bash`
   - เข้ากันได้กับ Linux commands
   - ง่ายกว่าการแปลงเป็น PowerShell ทั้งหมด

### ❌ สิ่งที่ต้องหลีกเลี่ยงบน Windows

1. ❌ ไม่ใช้ Self-Hosted Runner กับ Public Repository
2. ❌ ไม่ ignore `package-lock.json` ใน `.gitignore`
3. ❌ ไม่ใช้ `npm install --production` ใน Dockerfile
4. ❌ ไม่รัน runner ด้วย admin account เสมอ
5. ❌ ไม่ hard-code secrets ในโค้ด
6. ❌ ไม่ลืมติดตั้ง Git Bash (จาก Git for Windows)

### 🪟 เฉพาะสำหรับ Windows

1. ✅ ติดตั้ง Git for Windows (รวม Git Bash)
2. ✅ ใช้ PowerShell 7+ หรือ Windows PowerShell
3. ✅ Enable Docker Desktop WSL 2 backend
4. ✅ รัน Runner เป็น Windows Service
5. ✅ ใช้ monitor.ps1 แทน monitor.sh
6. ✅ ตรวจสอบ Windows Firewall settings

---

## 💡 Troubleshooting บน Windows

### ปัญหา 1: Runner ไม่ start

**Solution:**
```powershell
# ตรวจสอบ service
.\svc.cmd status

# ดู logs
Get-Content -Path "_diag\Runner_*.log" -Tail 100

# Restart service
.\svc.cmd stop
.\svc.cmd start
```

### ปัญหา 2: Docker Desktop ไม่ทำงาน

**Solution:**
1. เปิด Docker Desktop
2. ตรวจสอบว่า WSL 2 backend enabled
3. รัน PowerShell as Administrator:
   ```powershell
   docker ps
   ```

### ปัญหา 3: PowerShell ไม่ให้รัน scripts

**Solution:**
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### ปัญหา 4: Git Bash ไม่เจอ

**Solution:**
- ติดตั้ง Git for Windows: https://git-scm.com/download/win
- ตรวจสอบว่า Git Bash ถูกติดตั้ง
- เพิ่ม Git Bash ใน PATH

### ปัญหา 5: Port 8080 ถูกใช้งานแล้ว

**Solution:**
```powershell
# ดูว่า process ไหนใช้ port 8080
netstat -ano | findstr :8080

# ปิด process (ใส่ PID จากคำสั่งด้านบน)
taskkill /PID <PID> /F

# หรือเปลี่ยน port ใน docker-compose.yml
# "8081:80" แทน "8080:80"
```

---

## คำถามท้ายบท

### 1. Pull-based Model ของ Self-Hosted Runner คืออะไร มีข้อดีอย่างไร

<details>
<summary>คำตอบ</summary>

เขียนคำตอบลงในช่องนี้

</details>

### 2. ทำไม Pull-based ปลอดภัยกว่า Push-based

<details>
<summary>คำตอบ</summary>

เขียนคำตอบลงในช่องนี้

</details>

### 3. ทำไมต้องใช้ npm ci แทน npm install ใน production

<details>
<summary>คำตอบ</summary>

เขียนคำตอบลงในช่องนี้

</details>

### 4. ทำไมห้ามใช้ Self-Hosted Runner กับ Public Repository

<details>
<summary>คำตอบ</summary>

เขียนคำตอบลงในช่องนี้

</details>

### 5. Nginx คืออะไร และการทำ Reverse Proxy ใน Nginx มีความสำคัญอย่างไร

<details>
<summary>คำตอบ</summary>

เขียนคำตอบลงในช่องนี้

</details>

### 6. ความแตกต่างระหว่างการรัน Runner บน Windows และ Linux คืออะไร

<details>
<summary>คำตอบ</summary>

เขียนคำตอบลงในช่องนี้

</details>

---

## 📚 เอกสารอ้างอิง

- [GitHub Actions Self-Hosted Runners](https://docs.github.com/en/actions/hosting-your-own-runners)
- [Self-Hosted Runner on Windows](https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners/about-self-hosted-runners#requirements-for-self-hosted-runner-machines)
- [npm ci Documentation](https://docs.npmjs.com/cli/v10/commands/npm-ci)
- [Docker Multi-stage Builds](https://docs.docker.com/build/building/multi-stage/)
- [Nginx Reverse Proxy Guide](https://docs.nginx.com/nginx/admin-guide/web-server/reverse-proxy/)
- [Git for Windows](https://git-scm.com/download/win)
- [PowerShell Documentation](https://learn.microsoft.com/en-us/powershell/)
- [Docker Desktop for Windows](https://docs.docker.com/desktop/install/windows-install/)

---

## 🎓 สิ่งที่ได้เรียนรู้

เมื่อทำใบงานนี้จนเสร็จ คุณจะได้เรียนรู้:

✅ วิธีติดตั้ง Self-Hosted Runner บน Windows
✅ การใช้ Git Bash บน Windows สำหรับ CI/CD
✅ การสร้าง CI/CD Pipeline ด้วย GitHub Actions
✅ การ Deploy แอปพลิเคชันด้วย Docker บน Windows
✅ การตั้งค่า Nginx Reverse Proxy
✅ การ Monitor และ Troubleshoot บน Windows
✅ ความแตกต่างระหว่าง Windows และ Linux ใน DevOps

---

**🎉 ขอให้สนุกกับการเรียนรู้!**
