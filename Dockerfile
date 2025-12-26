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
LABEL description="Production Node.js Application"
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