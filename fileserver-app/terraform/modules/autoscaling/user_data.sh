#!/bin/bash
yum update -y

# Install necessary packages
yum install -y nginx docker git

# Start and enable services
systemctl start docker
systemctl enable docker
systemctl start nginx
systemctl enable nginx

# Add ec2-user to docker group
usermod -a -G docker ec2-user

# Install Docker Compose
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Install Node.js and npm
curl -fsSL https://rpm.nodesource.com/setup_18.x | bash -
yum install -y nodejs

# Configure Nginx as reverse proxy
cat > /etc/nginx/nginx.conf << "NGINXEOF"
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log;
pid /run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    log_format main "\$remote_addr - \$remote_user [\$time_local] \"\$request\" "
                    "\$status \$body_bytes_sent \"\$http_referer\" "
                    "\"\$http_user_agent\" \"\$http_x_forwarded_for\"";

    access_log /var/log/nginx/access.log main;

    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;

    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    upstream app_backend {
        server ${app_server_ip}:8000;
    }

    server {
        listen 80 default_server;
        listen [::]:80 default_server;
        server_name _;
        root /var/www/html;

        location /api/ {
            proxy_pass http://app_backend;
            proxy_http_version 1.1;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
            proxy_cache_bypass \$http_upgrade;
            proxy_connect_timeout 30s;
            proxy_send_timeout 30s;
            proxy_read_timeout 30s;
        }

        location / {
            try_files \$uri \$uri/ /index.html;
        }

        error_page 404 /404.html;
            location = /40x.html {
        }

        error_page 500 502 503 504 /50x.html;
            location = /50x.html {
        }
    }
}
NGINXEOF

# Create application directory structure
mkdir -p /home/ec2-user/fileserver-app/client/src
cd /home/ec2-user/fileserver-app/client

# Create package.json for client
cat > package.json << "PKGEOF"
{
  "name": "fileserver-frontend",
  "version": "1.0.0",
  "description": "File Server Frontend - React.js application for file management",
  "type": "module",
  "scripts": {
    "dev": "vite",
    "build": "vite build",
    "preview": "vite preview"
  },
  "dependencies": {
    "react": "^18.2.0",
    "react-dom": "^18.2.0",
    "axios": "^1.6.2"
  },
  "devDependencies": {
    "@vitejs/plugin-react": "^4.2.1",
    "vite": "^5.0.8",
    "tailwindcss": "^3.3.6",
    "autoprefixer": "^10.4.16",
    "postcss": "^8.4.32"
  }
}
PKGEOF

# Create vite.config.js
cat > vite.config.js << "VITEEOF"
import { defineConfig } from "vite"
import react from "@vitejs/plugin-react"

export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    host: true
  },
  build: {
    outDir: "dist",
    sourcemap: false,
    minify: "terser"
  }
})
VITEEOF

# Create tailwind.config.js
cat > tailwind.config.js << "TAILWINDEOF"
export default {
  content: [
    "./index.html",
    "./src/**/*.{js,ts,jsx,tsx}",
  ],
  theme: {
    extend: {
      colors: {
        primary: {
          50: "#eff6ff",
          500: "#3b82f6",
          600: "#2563eb",
          700: "#1d4ed8",
        }
      }
    },
  },
  plugins: [],
}
TAILWINDEOF

# Create postcss.config.js
cat > postcss.config.js << "POSTCSSEOF"
export default {
  plugins: {
    tailwindcss: {},
    autoprefixer: {},
  },
}
POSTCSSEOF

# Create index.html
cat > index.html << "HTMLEOF"
<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>File Server</title>
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="/src/main.jsx"></script>
  </body>
</html>
HTMLEOF

# Create main.jsx
cat > src/main.jsx << "MAINEOF"
import React from "react"
import ReactDOM from "react-dom/client"
import App from "./App.jsx"
import "./App.css"

ReactDOM.createRoot(document.getElementById("root")).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
)
MAINEOF

# Create App.css
cat > src/App.css << "CSSEOF"
@tailwind base;
@tailwind components;
@tailwind utilities;

:root {
  font-family: Inter, system-ui, Avenir, Helvetica, Arial, sans-serif;
  line-height: 1.5;
  font-weight: 400;
}

.loading-spinner {
  border: 2px solid #f3f3f3;
  border-top: 2px solid #3498db;
  border-radius: 50%;
  width: 20px;
  height: 20px;
  animation: spin 1s linear infinite;
  display: inline-block;
  margin-right: 8px;
}

@keyframes spin {
  0% { transform: rotate(0deg); }
  100% { transform: rotate(360deg); }
}
CSSEOF

# Create React App.jsx - Main Application
cat > src/App.jsx << "REACTEOF"
import React, { useState, useEffect } from "react";
import axios from "axios";
import "./App.css";

const API_BASE_URL = "/api";
axios.defaults.baseURL = API_BASE_URL;

function App() {
  const [user, setUser] = useState(null);
  const [files, setFiles] = useState([]);
  const [loading, setLoading] = useState(true);
  const [uploading, setUploading] = useState(false);
  const [selectedFile, setSelectedFile] = useState(null);
  const [showLogin, setShowLogin] = useState(true);
  const [loginForm, setLoginForm] = useState({ username: "", password: "" });
  const [registerForm, setRegisterForm] = useState({ 
    username: "", 
    email: "", 
    password: "",
    confirmPassword: ""
  });
  const [emailForm, setEmailForm] = useState({ email: "", message: "", fileId: null });
  const [showEmailModal, setShowEmailModal] = useState(false);
  const [error, setError] = useState("");
  const [success, setSuccess] = useState("");

  useEffect(() => {
    const token = localStorage.getItem("token");
    if (token) {
      axios.defaults.headers.common["Authorization"] = "Bearer " + token;
      fetchUser();
      fetchFiles();
    } else {
      setLoading(false);
    }
  }, []);

  const fetchUser = async () => {
    try {
      const response = await axios.get("/user");
      setUser(response.data);
    } catch (error) {
      console.error("Failed to fetch user:", error);
      logout();
    }
  };

  const fetchFiles = async () => {
    try {
      const response = await axios.get("/files");
      setFiles(response.data);
      setLoading(false);
    } catch (error) {
      console.error("Failed to fetch files:", error);
      setError("Failed to load files");
      setLoading(false);
    }
  };

  const login = async (e) => {
    e.preventDefault();
    setError("");
    setSuccess("");
    
    try {
      const response = await axios.post("/login", loginForm);
      const { token, user } = response.data;
      
      localStorage.setItem("token", token);
      axios.defaults.headers.common["Authorization"] = "Bearer " + token;
      
      setUser(user);
      setLoginForm({ username: "", password: "" });
      fetchFiles();
    } catch (error) {
      setError(error.response?.data?.message || "Login failed");
    }
  };

  const register = async (e) => {
    e.preventDefault();
    setError("");
    setSuccess("");
    
    if (registerForm.password !== registerForm.confirmPassword) {
      setError("Passwords do not match");
      return;
    }
    
    try {
      await axios.post("/register", {
        username: registerForm.username,
        email: registerForm.email,
        password: registerForm.password
      });
      
      setSuccess("Registration successful! Please login.");
      setRegisterForm({ username: "", email: "", password: "", confirmPassword: "" });
      setShowLogin(true);
    } catch (error) {
      setError(error.response?.data?.message || "Registration failed");
    }
  };

  const logout = () => {
    localStorage.removeItem("token");
    delete axios.defaults.headers.common["Authorization"];
    setUser(null);
    setFiles([]);
  };

  const uploadFile = async () => {
    if (!selectedFile) {
      setError("Please select a file");
      return;
    }
    
    setUploading(true);
    setError("");
    setSuccess("");
    
    const formData = new FormData();
    formData.append("file", selectedFile);
    
    try {
      await axios.post("/upload", formData, {
        headers: { "Content-Type": "multipart/form-data" }
      });
      
      setSuccess("File uploaded successfully!");
      setSelectedFile(null);
      document.getElementById("file-input").value = "";
      fetchFiles();
    } catch (error) {
      setError(error.response?.data?.message || "Upload failed");
    } finally {
      setUploading(false);
    }
  };

  const downloadFile = async (fileId, fileName) => {
    try {
      const response = await axios.get("/download/" + fileId, {
        responseType: "blob"
      });
      
      const url = window.URL.createObjectURL(new Blob([response.data]));
      const link = document.createElement("a");
      link.href = url;
      link.download = fileName;
      document.body.appendChild(link);
      link.click();
      link.remove();
      window.URL.revokeObjectURL(url);
    } catch (error) {
      setError("Failed to download file");
    }
  };

  const deleteFile = async (fileId) => {
    if (!window.confirm("Are you sure you want to delete this file?")) {
      return;
    }
    
    try {
      await axios.delete("/files/" + fileId);
      setSuccess("File deleted successfully!");
      fetchFiles();
    } catch (error) {
      setError("Failed to delete file");
    }
  };

  const sendFileEmail = async (e) => {
    e.preventDefault();
    setError("");
    setSuccess("");
    
    try {
      const response = await axios.post("/send-file/" + emailForm.fileId, {
        email: emailForm.email,
        message: emailForm.message
      });
      
      setSuccess(response.data.message);
      setShowEmailModal(false);
      setEmailForm({ email: "", message: "", fileId: null });
    } catch (error) {
      setError(error.response?.data?.message || "Failed to send email");
    }
  };

  const openEmailModal = (fileId) => {
    setEmailForm({ ...emailForm, fileId });
    setShowEmailModal(true);
  };

  const formatFileSize = (bytes) => {
    if (bytes === 0) return "0 Bytes";
    const k = 1024;
    const sizes = ["Bytes", "KB", "MB", "GB"];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + " " + sizes[i];
  };

  const formatDate = (dateString) => {
    return new Date(dateString).toLocaleDateString() + " " + 
           new Date(dateString).toLocaleTimeString();
  };

  if (loading) {
    return (
      React.createElement("div", { className: "min-h-screen bg-gray-100 flex items-center justify-center" },
        React.createElement("div", { className: "text-xl" }, "Loading...")
      )
    );
  }

  if (!user) {
    return (
      React.createElement("div", { className: "min-h-screen bg-gray-100 flex items-center justify-center" },
        React.createElement("div", { className: "max-w-md w-full bg-white rounded-lg shadow-md p-6" },
          React.createElement("h1", { className: "text-2xl font-bold text-center mb-6" }, "File Server"),
          
          error && React.createElement("div", { className: "bg-red-100 border border-red-400 text-red-700 px-4 py-3 rounded mb-4" }, error),
          success && React.createElement("div", { className: "bg-green-100 border border-green-400 text-green-700 px-4 py-3 rounded mb-4" }, success),
          
          React.createElement("div", { className: "flex mb-4" },
            React.createElement("button", { 
              className: "flex-1 py-2 px-4 " + (showLogin ? "bg-blue-500 text-white" : "bg-gray-200 text-gray-700"),
              onClick: () => setShowLogin(true)
            }, "Login"),
            React.createElement("button", { 
              className: "flex-1 py-2 px-4 " + (!showLogin ? "bg-blue-500 text-white" : "bg-gray-200 text-gray-700"),
              onClick: () => setShowLogin(false)
            }, "Register")
          ),
          
          showLogin ? 
            React.createElement("form", { onSubmit: login },
              React.createElement("div", { className: "mb-4" },
                React.createElement("label", { className: "block text-gray-700 text-sm font-bold mb-2" }, "Username"),
                React.createElement("input", {
                  type: "text",
                  value: loginForm.username,
                  onChange: (e) => setLoginForm({...loginForm, username: e.target.value}),
                  className: "shadow appearance-none border rounded w-full py-2 px-3 text-gray-700 leading-tight focus:outline-none focus:shadow-outline",
                  required: true
                })
              ),
              React.createElement("div", { className: "mb-6" },
                React.createElement("label", { className: "block text-gray-700 text-sm font-bold mb-2" }, "Password"),
                React.createElement("input", {
                  type: "password",
                  value: loginForm.password,
                  onChange: (e) => setLoginForm({...loginForm, password: e.target.value}),
                  className: "shadow appearance-none border rounded w-full py-2 px-3 text-gray-700 leading-tight focus:outline-none focus:shadow-outline",
                  required: true
                })
              ),
              React.createElement("button", {
                type: "submit",
                className: "bg-blue-500 hover:bg-blue-700 text-white font-bold py-2 px-4 rounded focus:outline-none focus:shadow-outline w-full"
              }, "Login")
            ) :
            React.createElement("form", { onSubmit: register },
              React.createElement("div", { className: "mb-4" },
                React.createElement("label", { className: "block text-gray-700 text-sm font-bold mb-2" }, "Username"),
                React.createElement("input", {
                  type: "text",
                  value: registerForm.username,
                  onChange: (e) => setRegisterForm({...registerForm, username: e.target.value}),
                  className: "shadow appearance-none border rounded w-full py-2 px-3 text-gray-700 leading-tight focus:outline-none focus:shadow-outline",
                  required: true
                })
              ),
              React.createElement("div", { className: "mb-4" },
                React.createElement("label", { className: "block text-gray-700 text-sm font-bold mb-2" }, "Email"),
                React.createElement("input", {
                  type: "email",
                  value: registerForm.email,
                  onChange: (e) => setRegisterForm({...registerForm, email: e.target.value}),
                  className: "shadow appearance-none border rounded w-full py-2 px-3 text-gray-700 leading-tight focus:outline-none focus:shadow-outline",
                  required: true
                })
              ),
              React.createElement("div", { className: "mb-4" },
                React.createElement("label", { className: "block text-gray-700 text-sm font-bold mb-2" }, "Password"),
                React.createElement("input", {
                  type: "password",
                  value: registerForm.password,
                  onChange: (e) => setRegisterForm({...registerForm, password: e.target.value}),
                  className: "shadow appearance-none border rounded w-full py-2 px-3 text-gray-700 leading-tight focus:outline-none focus:shadow-outline",
                  required: true
                })
              ),
              React.createElement("div", { className: "mb-6" },
                React.createElement("label", { className: "block text-gray-700 text-sm font-bold mb-2" }, "Confirm Password"),
                React.createElement("input", {
                  type: "password",
                  value: registerForm.confirmPassword,
                  onChange: (e) => setRegisterForm({...registerForm, confirmPassword: e.target.value}),
                  className: "shadow appearance-none border rounded w-full py-2 px-3 text-gray-700 leading-tight focus:outline-none focus:shadow-outline",
                  required: true
                })
              ),
              React.createElement("button", {
                type: "submit",
                className: "bg-green-500 hover:bg-green-700 text-white font-bold py-2 px-4 rounded focus:outline-none focus:shadow-outline w-full"
              }, "Register")
            )
        )
      )
    );
  }

  return React.createElement("div", { className: "min-h-screen bg-gray-100" }, "Loading main app...");
}

export default App;
REACTEOF

# Install dependencies and build frontend
npm install
npm run build

# Copy built files to nginx document root
cp -r dist/* /var/www/html/

# Install and configure CloudWatch agent
yum install -y amazon-cloudwatch-agent

# CloudWatch agent configuration
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << "CWEOF"
{
  "agent": {
    "metrics_collection_interval": 60,
    "run_as_user": "cwagent"
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/nginx/access.log",
            "log_group_name": "/aws/ec2/nginx/access",
            "log_stream_name": "{instance_id}"
          },
          {
            "file_path": "/var/log/nginx/error.log",
            "log_group_name": "/aws/ec2/nginx/error",
            "log_stream_name": "{instance_id}"
          }
        ]
      }
    }
  },
  "metrics": {
    "namespace": "CWAgent",
    "metrics_collected": {
      "cpu": {
        "measurement": [
          "cpu_usage_idle",
          "cpu_usage_iowait",
          "cpu_usage_user",
          "cpu_usage_system"
        ],
        "metrics_collection_interval": 60
      },
      "disk": {
        "measurement": [
          "used_percent"
        ],
        "metrics_collection_interval": 60,
        "resources": [
          "*"
        ]
      },
      "mem": {
        "measurement": [
          "mem_used_percent"
        ],
        "metrics_collection_interval": 60
      }
    }
  }
}
CWEOF

# Start CloudWatch agent
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json -s

# Restart nginx to apply new configuration
systemctl restart nginx

# Change ownership
chown -R ec2-user:ec2-user /home/ec2-user