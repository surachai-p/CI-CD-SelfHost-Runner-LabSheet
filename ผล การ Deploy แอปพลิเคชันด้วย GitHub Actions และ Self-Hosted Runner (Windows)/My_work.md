บันทึกรูปผลการทดลอง
บันทึกรูปหน้า Runners โดยคัดลอกให้เห็น Account ของ GitHub และ Repository
และแสดง Runner status เป็น "Idle" สีเขียว
<img width="1919" height="1014" alt="image" src="https://github.com/user-attachments/assets/4f01edff-19f9-4a32-8835-52f00b6da607" />



--
บันทึกผลการรันคำสั่ง docker logs
--
<img width="1599" height="894" alt="image" src="https://github.com/user-attachments/assets/466c0d53-cd02-4a0a-adee-13c6bae2a69b" />


--
คำถามท้ายบท
--

1. Pull-based Model ของ Self-Hosted Runner คืออะไร มีข้อดีอย่างไร
คำตอบ ข้อดี  ปลอดภัยกว่า เพราะไม่ต้องเปิดพอร์ตให้คนภายนอกเข้ามา เครื่อง Runner อยู่หลัง Firewall ได้ ควบคุมได้ง่าย เหมาะกับระบบองค์กร ลดความเสี่ยงจากการโจมตีภายนอก
3. ทำไม Pull-based ปลอดภัยกว่า Push-based
คำตอบ เพราะ Pull-based ไม่ต้องเปิดเครื่องให้รับคำสั่งจากภายนอก ที่จะเสียงโดนโจมตีได้
4. ทำไมต้องใช้ npm ci แทน npm install ใน production
คำตอบ ติดตั้งเร็วกว่า ผลลัพธ์เหมือนกันทุกครั้ง (ลดปัญหา “รันเครื่องนี้ได้ แต่อีกเครื่องไม่ได้”)
5. ทำไมห้ามใช้ Self-Hosted Runner กับ Public Repository
คำตอบ Runner จะรันโค้ดนั้นบนเครื่องเราโดยตรง เสี่ยงโดนขโมยข้อมูล / ควบคุมเครื่อง
6. Nginx คืออะไร และการทำ Reverse Proxy ใน Nginx มีความสำคัญอย่างไร
คำตอบ Nginx คือ Web Server รับ request จากผู้ใช้ ส่งต่อไปยัง Backend (เช่น Node.js, API, Docker container) ซ่อนโครงสร้างระบบภายใน เพิ่มความปลอดภัย
7. ความแตกต่างระหว่างการรัน Runner บน Windows และ Linux คืออะไร  
ตอบ Windows เหมาะกับเรียน ทดสอบ  Linux  เหมาะกับใช้งานจริงและระบบเซิร์ฟเวอร์ และยังทำง่ายตามใบงาน ครั้งแรก แต่งต่างกับ window ที่ทำไม่ผ่าน
