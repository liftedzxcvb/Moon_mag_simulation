function y = pe2pl(PE,BW,z,a)

y = a^2/(z*BW)*exp(-2.*PE.^2/BW.^2);

end