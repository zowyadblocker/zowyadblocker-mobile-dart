# Root and Shizuku safety

Root filtering is not implemented in 0.1.0. The UI does not install a module,
remount partitions, edit hosts, redirect DNS, change Private DNS or alter firewall
rules. The explicit root diagnostic runs exactly `su -c id`, waits up to 15
seconds and requires a successful exit with UID 0. A binary's presence is not
authorization. Denial is reported rather than treated as usable root.

To use another systemless hosts solution, install and manage it through its own
documented root-manager workflow. Do not copy ad hoc commands into `/system`.
Magisk, KernelSU and APatch differ; no support claim is made for any hosts mounting
mechanism in this build. Zowy has no root configuration to restore. Uninstalling
Zowy leaves no root module behind.

If DNS filtering breaks an app: stop Zowy; if Android immediately restarts it,
disable Zowy's always-on VPN in Android VPN settings. Do not enable lockdown for
this DNS-only VPN. Revoke/delete its VPN profile if necessary. You can restore
the previous saved settings from Settings or import a previously exported backup.
User rules are not replaced by list updates.

Install/start Shizuku yourself, then request permission from Zowy Settings. The
report distinguishes disconnected, ungranted, shell UID 2000 and root UID 0. Binder
death/restart updates availability. On non-root devices Shizuku normally requires
restart after boot. It supplies diagnostics here, not a local filtering backend.
Remote filtering Private DNS, if configured outside Zowy, is the remote provider's
policy and does not use Zowy's local rules.
