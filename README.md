# mautic-aws-server-setup
This is a setup guide for Mautic on AWS

# Mautic 5 AWS EC2 Setup Script

## Purpose
This repository contains a shell script and detailed setup instructions to automate the installation and configuration of **Mautic 5** on an AWS EC2 instance running **Ubuntu 24.04**. The goal is to simplify the deployment process and provide a reusable solution for others setting up Mautic in a cloud environment.

## What is Mautic?
Mautic is an open-source marketing automation platform that allows businesses to manage email campaigns, create landing pages, track user behavior, and much more. It is a powerful tool for marketers looking to automate their workflows and improve user engagement.

Key Features:
- Dynamic email content and personalized campaigns.
- Advanced segmentation and targeting.
- Integration with CRM, social media, and other tools.
- REST API for extensibility and automation.

Use Cases:
- Email marketing campaigns.
- Customer journey automation.
- Lead management and tracking.
- API-driven marketing workflows.

## Prerequisites
Before running the shell script, ensure the following preparatory steps are completed:

### 1. Create a Static IP (Elastic IP) for the Server
- Allocate an Elastic IP in the AWS Management Console.
- Reserve this IP for the Mautic server to ensure consistent DNS routing.

### 2. Set Up DNS Records
- Create an **A record** pointing your Mautic domain (e.g., `mautic.example.com`) to the Elastic IP.
- Optionally, set up a **CNAME record** for any subdomains if needed.

### 3. Configure Security Groups
Define and attach appropriate security rules:
1. **SSH Access**:
   - Allow inbound traffic on port 22.
   - Restrict access to your IP or a small set of known IPs.
2. **Frontend Access**:
   - Open ports 80 (HTTP) and 443 (HTTPS) for admin and API usage.
   - Restrict access to authorized IPs if it’s a private setup.
3. **API Access**:
   - Allow inbound traffic on port 443 from the mobile application server or other clients using the Mautic API.

### 4. Launch an Ubuntu 24.04 EC2 Instance
- Select an official Ubuntu 24.04 minimal image.
- Attach the previously defined security groups to the instance.
- Assign the reserved Elastic IP to the instance.

### 5. Set Up SSH Key Pair
- Use an existing key pair or create a new one for secure SSH access.
- Ensure the private key is available locally for the admin performing the setup.

### 6. Test Connectivity
- Verify SSH access to the server before proceeding with the script.

### 7. Backup Strategy (Optional)
- Plan for instance snapshots or backup the server files and database regularly.
- Ensure Elastic IP and DNS records can be redirected in case of redeployment.

## Usage
1. Clone this repository to your local machine:
   ```bash
   git clone https://github.com/yourusername/mautic-aws-setup.git
   cd mautic-aws-setup
   ```

2. Edit the shell script to customize any domain-specific or configuration-specific details.

3. SSH into your AWS EC2 instance and copy the script:
   ```bash
   scp setup_mautic.sh ubuntu@<your-ec2-ip>:/home/ubuntu/
   ```

4. Run the script:
   ```bash
   chmod +x setup_mautic.sh
   ./setup_mautic.sh
   ```

5. Follow any additional prompts or configurations detailed in the script.

## License
This repository is open-source and available under the MIT License. Feel free to fork, contribute, or modify as needed.

---
For questions or contributions, please open an issue or submit a pull request!
