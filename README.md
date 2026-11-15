# homeserver-scripts

一台旧电脑装上 Ubuntu Server，敲一行命令，就变成家里的智能家居中枢 + 相册备份 + 共享盘。

这里是「Eric 瞎折腾」视频里用到的一键脚本合集，代码全部公开，运行之前可以先看一眼里面做了什么。

- B 站：[s.mwxw.com/bili](https://s.mwxw.com/bili)
- YouTube：[@erictinkers](https://www.youtube.com/@erictinkers)
- 网站：[mwxw.com](https://mwxw.com)

## 一键命令

在 Ubuntu Server 的命令行里，用你自己的登录用户（不是 root）运行：

| 命令 | 装什么 | 装好后的地址 |
|---|---|---|
| `curl -sL s.mwxw.com/ha \| sudo bash` | Docker + Home Assistant + ESPHome | `http://服务器IP:8123`（HA）<br>`http://服务器IP:6052`（ESPHome） |
| `curl -sL s.mwxw.com/home \| sudo bash` | Immich 相册（精简版，不带 AI）+ Samba 共享文件夹 | `http://服务器IP:2283`（相册）<br>`\\服务器IP\share`（共享文件夹） |

短链接下载的就是本仓库里的 [`ha.sh`](ha.sh) 和 [`home.sh`](home.sh)，内容完全一样（放在国内能访问的 CDN 上，因为 GitHub 在国内经常连不上）。

两条命令互不依赖，可以只装一个，也可以都装；重复运行也没关系，已经装好的部分会跳过。

## 脚本做了什么

### ha.sh

1. 从 Ubuntu 官方软件源安装 Docker
2. 自动测速，挑最快的国内镜像下载 Home Assistant 和 ESPHome（稳定版）
3. 在 `/opt/homeserver/` 下生成 `docker-compose.yml` 并启动
4. 等 Home Assistant 第一次启动完成，打印访问地址

### home.sh

1. 先让你设一个共享文件夹密码（用户名就是你的登录用户名）
2. 安装 Samba（共享文件夹）和 Docker
3. 创建共享文件夹 `/srv/share`，电视盒子（如 Kodi）、Windows、手机都能通过 SMB 访问
4. 自动测速挑镜像，下载 Immich，照片存在 `/srv/photos`
5. 启动 Immich，打印访问地址。数据库密码在你自己的机器上随机生成

Immich 用的是精简模式（关闭了人脸识别和智能搜索），旧电脑也能跑得动。

## 说明

- 只支持 Ubuntu / Debian 系统，推荐 Ubuntu Server LTS 版本
- 脚本会把系统时区设成 `Asia/Shanghai`
- 命令行界面显示不了中文，所以脚本里的提示都是英文
- 测速只是访问各个镜像站，不会向任何地方发送你的信息

## 卸载

> ⚠️ 下面的删除命令会删掉对应的配置和数据（照片也在里面），删了恢复不了，确认不要了再执行。

```bash
# 卸载 Home Assistant + ESPHome
sudo docker compose -f /opt/homeserver/docker-compose.yml down
sudo rm -rf /opt/homeserver/homeassistant /opt/homeserver/esphome /opt/homeserver/docker-compose.yml

# 卸载 Immich（照片在 /srv/photos）
sudo docker compose --project-directory /opt/homeserver/immich down
sudo rm -rf /opt/homeserver/immich /srv/photos
```

## 许可

[MIT](LICENSE)
