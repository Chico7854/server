# Shared by the prod and test server blocks in default.conf.

client_max_body_size 20m;

location = /healthz {
    default_type text/plain;
    return 200 "ok $env\n";
}

location = / {
    default_type text/plain;
    return 200 "Server is running ($env). Apps live under /<app-name>/\n";
}

# Redirect /investment to /investment/ so relative asset paths work.
location ~ ^/([a-z0-9-]+)$ {
    absolute_redirect off;
    return 301 $uri/$is_args$args;
}

location ~ ^/(?<app>[a-z0-9-]+)/ {
    # No URI after the port, so the full original path (/investment/...) is passed on.
    set $upstream http://$app-$env:3000;
    proxy_pass $upstream;

    proxy_http_version 1.1;
    proxy_set_header Host $http_host;
    proxy_set_header X-Real-IP $http_cf_connecting_ip;
    proxy_set_header X-Forwarded-For $http_cf_connecting_ip;
    proxy_set_header X-Forwarded-Proto https;
    proxy_set_header X-Forwarded-Prefix /$app;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection $connection_upgrade;
    proxy_read_timeout 300s;

    # Nginx reports 502 when no container named <app>-<env> exists.
    proxy_intercept_errors on;
    error_page 502 503 504 = @app_down;
}

location @app_down {
    default_type text/plain;
    return 502 "App '$app' is not running in $env.\n";
}
