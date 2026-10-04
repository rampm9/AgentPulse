# AgentPulse / AgentBar — Simple Product Guide 🚀

> The current product definition is [README.md](README.md). This guide describes an earlier, broader idea, including alerts and export that are not in the app.

> **What is this document?**  
> This is a simple, easy-to-read guide explaining what **AgentPulse** does, why it is super useful, and how all its cool features work! Written in plain and simple English so anyone (even a 6th-grade student) can understand it easily.

---

## 1. What is AgentPulse? 🤔

Imagine you get a monthly mobile data pack of 50 GB. You want to know how much internet data you used today so you don't run out of internet suddenly, right?

In the same way, software developers use smart AI tools like **Claude Code**, **Cursor**, **GitHub Copilot**, and **OpenAI** to help them write computer code. But these AI tools charge money based on **tokens** (words or code snippets processed). 

If developers are not careful, AI can quickly use up a lot of money!

**AgentPulse** is a tiny, beautiful app that sits right on top of your Mac screen in the menu bar (near the battery and Wi-Fi icons). It shows you in real-time:
* 🟢 Is your AI tool active right now?
* 📊 How many tokens and dollars did you spend today?
* ⚠️ Are you about to cross your daily budget limit?

---

## 2. What Cool Features Does It Have? ✨

### 🤖 1. Multi-Tool Tracker
You can track all your favorite AI helpers in one place:
- **Claude Code**
- **Cursor AI**
- **GitHub Copilot**
- **OpenAI API (ChatGPT models)**
- **Gemini CLI**

### 🔔 2. Custom Budget Alerts
Set your daily spending budget (for example: $5.00 per day).  
When you hit:
- **50% of budget**: App gently reminds you.
- **80% of budget**: App gives a warning notification.
- **100% of budget**: Red alert badge so you don't accidentally overspend your money!

### 🎯 3. Daily Usage Goal Tracker
Just like a fitness app tracks your 10,000 steps goal per day, AgentPulse lets you set a daily token goal (e.g., 100,000 tokens/day). A glowing ring shows your daily progress!

### 📥 4. Export Your Data (CSV / JSON)
Want to show your manager or client how much AI was used for a project? Click one button to download your daily usage report as a CSV file (Excel sheet) or JSON file!

### 💎 5. Super Sleek macOS "Glassmorphism" Design
- **Blur Glass Visuals**: Translucent glass background that matches your Mac desktop.
- **Interactive Charts**: Hover over daily charts to see hourly usage spikes.
- **Smooth Animations**: Micro-animations for buttons, tabs, and budget rings.

---

## 3. How Does It Work Behind the Scenes? ⚙️

```
[ Your AI Tools ] ──> ( Logs & Usage Files ) ──> [ AgentPulse Engine ] ──> [ Glass Menu Bar App ]
 (Claude, Cursor,                                   (Calculates Costs       (Live Updates &
  Copilot, OpenAI)                                    & Budget Alerts)        Interactive Charts)
```

1. **Automatic File Watching**: Whenever your AI tool writes code, it saves a log file in your computer. AgentPulse instantly notices this change without slowing down your Mac.
2. **Cost Calculator**: It matches the AI model name with exact official prices to compute your cost in cents and dollars.
3. **Live Screen Update**: The numbers on your menu bar update instantly!

---

## 4. Quick Summary Table 📋

| Feature | What it does | Why it helps you |
| :--- | :--- | :--- |
| **Menu Bar Pulse** | Glows green when AI is working | Know when AI is busy without opening extra windows |
| **Glass Panel** | Beautiful dashboard popover | View all stats at a glance |
| **Charts** | Visual bar & line graphs | See peak usage hours during your workday |
| **Goal Tracker** | Progress ring for tokens | Stay disciplined with your daily usage |
| **Budget Alerts** | Notifications at 50%, 80%, 100% | Prevents sudden high credit card bills |
| **Data Export** | Save as CSV or JSON | Easy reporting for team or client billing |
