# displaylink-installer
Helper script for semi-automatic installation of the official Synaptics DisplayLink driver with Secure Boot support.

## Disclaimer:
This script was thoroughly tested. Yet, it uses sudo excessively and pokes into kernel modules, therefore use it at your own peril. I take zero responsibility for deletion of your private "home video collection", damaged system, small black holes formed inside your PC case or any other shinanigans this could possibly cause.

## Note:
No modifications are made to the official driver or its installer in any way, it just automates and simplifies some painful steps of the process. 

The main focus is to allow users to install the driver on systems with active Secure Boot, while adding some useful functions like the ability to remove corrupted EVDI installation.

Tested on: 
- Ubuntu 22.04 - fully functional
- Debian 11.5 - fully functional (except one missing echo message caused by differences in the installation process of official installer - nothing harmful) 

