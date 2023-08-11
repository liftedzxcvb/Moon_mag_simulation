function y = fovout(pe,fov)

if abs(real(pe)) > fov
    y = 1;
elseif abs(imag(pe)) > fov
    y = 1;
else
    y = 0;
end
end