# Use an official Debian image as a base
FROM debian:buster-slim AS build

# Install dependencies (for Dart SDK installation)
RUN apt-get update && apt-get install -y \
    wget \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg

# Add Dart SDK APT repository
RUN wget -qO- https://storage.googleapis.com/download.dartlang.org/linux/debian/dart_stable_amd64.deb > dart_stable.deb && \
    dpkg -i dart_stable.deb && \
    apt-get update && \
    apt-get install dart

# Check Dart SDK version (should show Dart 3.5.4 or higher)
RUN dart --version

WORKDIR /app
COPY pubspec.yaml pubspec.lock ./
RUN dart pub get

# Copy app files and compile the Dart app to an executable
COPY . .
RUN dart compile exe bin/referral_bot.dart -o bin/bot

# Final stage with minimal image for running the app
FROM debian:buster-slim

# Install necessary dependencies for running the bot
RUN apt-get update && apt-get install -y ca-certificates

WORKDIR /app
COPY --from=build /app/bin/bot ./  # Copy compiled binary
COPY --from=build /app/assets ./assets  # Copy assets if needed

CMD ["./bot"]  # Running the compiled Dart bot
