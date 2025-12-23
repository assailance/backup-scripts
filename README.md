<table>
  <tr>
    <td><img src="images/backup-postgres.png"></td>
    <td><img width="800" src="images/notification.png"></td>
  </tr>
</table>

Simple **bash scripts** for creating **backups** and sending them to Telegram.

# 🔩 Running scripts

To use **any** script, make the file **executable**:
```bash
chmod +x backup-folder.sh
chmod +x backup-docker-volume.sh
chmod +x backup-docker-postgres.sh
```

## Backup folder

You must specify the **backup name** and **path** to the directory.

**Usage:**
```bash
backup-folder.sh <backup_name> <directory_path>
```

**Examples:**
```bash
backup-folder.sh Name ./images
backup-folder.sh "Few words" /var/log/nginx
```

## Backup volume (Docker)

You must specify the **volume name**. The script will **automatically** check if it **exists**.

**Usage:**
```bash
backup-docker-volume.sh <docker_volume>
```

**Examples:**
```bash
backup-docker-volume.sh pg-data
backup-docker-volume.sh random-volume  # Docker volume does not exist: random-volume
```

## Backup postgres (Docker)

You must specify the **container name** (or **id**), **database name**, and **user name**.

**Usage:**
```bash
backup-docker-postgres.sh <postgres_container> <db_name> <db_user>
```

**Examples:**
```bash
backup-docker-volume.sh 5cee88979da6 my-database my-user
backup-docker-volume.sh random-name db user  # Docker container does not exist: random-name
```

> [!WARNING]
> When backing up a **directory** or a **Docker volume**, the data may be **actively modified** at the time of backup (for example by an application, service, or database).
>
> In such cases, the backup:
> - may contain partially written files
> - may become inconsistent
> - may fail to restore correctly later

## 🖼️ Other images

<table align="center">
  <tr>
    <td><img src="images/backup-volume.png"></td>
  </tr>
  <tr>
    <td><img src="images/backup-folder.png"></td>
  </tr>
</table>
