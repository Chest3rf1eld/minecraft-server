# Keeps the test world small and quick to test proximity voice in:
# DiscordSRV's default voice.yml disconnects around ~85 blocks apart
# (Horizontal Strength 80 + Falloff 5), so a 200-block border centered on
# spawn gives room to walk fully out of range and back without leaving a
# tiny, easy-to-navigate area.
worldborder center 0 0
worldborder set 200
time set day
weather clear
