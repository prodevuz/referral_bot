FROM dart:stable AS build

WORKDIR /app
COPY pubspec.* ./
RUN dart pub get

COPY . .
RUN dart compile exe bin/referral_bot.dart -o bin/bot

FROM debian:buster-slim
RUN apt-get update && apt-get install -y ca-certificates

WORKDIR /app
COPY --from=build /app/bin/bot ./
COPY --from=build /app/assets ./assets

CMD ["./bot"]