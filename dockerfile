FROM dart:3.5.4 AS build

WORKDIR /app
COPY pubspec.yaml pubspec.lock ./
RUN dart pub get

COPY . .
RUN dart compile exe bin/referral_bot.dart -o bin/bot

FROM debian:buster-slim
RUN apt-get update && apt-get install -y ca-certificates

WORKDIR /app
COPY --from=build /app/bin/bot ./
COPY --from=build /app/assets ./assets

CMD ["./bot"]