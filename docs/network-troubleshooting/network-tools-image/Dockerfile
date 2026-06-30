# Use the latest Fedora base image.
# Fedora is the upstream for Red Hat Enterprise Linux and is a great
# choice for a stable, secure, and community-supported base.
FROM fedora:latest

# Install network troubleshooting tools.
# The 'dnf' command is the standard package manager for Fedora.
# We also clean up the package manager cache to reduce image size.
RUN dnf update -y && \
    dnf install -y iputils procps-ng net-tools bind-utils tcpdump && \
    dnf clean all

# Define the user to run the container.
# OpenShift runs containers as a random non-root user by default,
# and this ensures compliance. The 'nobody' user is a common
# choice for running services that don't need any special permissions.
USER nobody

# Set the command to keep the container running indefinitely.
# This prevents the container from exiting immediately and avoids
# the CrashLoopBackOff state.
CMD tail -f /dev/null
